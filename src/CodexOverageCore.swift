import Foundation

// MARK: - Codex Credit Rate Card

/// Credits charged per million tokens for one model.
struct CodexCreditRates: Equatable {
    let input: Double
    let cachedInput: Double
    let output: Double
}

/// Usage past a Codex plan's limits draws down credits, billed per token by model.
/// Source: https://learn.chatgpt.com/docs/pricing (checked 2026-10-06).
enum CodexCreditRateCard {
    static let table: [String: CodexCreditRates] = [
        "gpt-6-astra": CodexCreditRates(input: 250, cachedInput: 25, output: 1250),
        "gpt-6.1-sol": CodexCreditRates(input: 50, cachedInput: 2.5, output: 250),
        "gpt-6-sol": CodexCreditRates(input: 50, cachedInput: 5, output: 250),
        "gpt-6-luna": CodexCreditRates(input: 2.5, cachedInput: 0.25, output: 12.5),
        "gpt-5.6-sol": CodexCreditRates(input: 100, cachedInput: 10, output: 500),
        "gpt-5.6-terra": CodexCreditRates(input: 50, cachedInput: 5, output: 300),
        "gpt-5.6-luna": CodexCreditRates(input: 5, cachedInput: 0.5, output: 30),
    ]

    /// Returns nil for a model the card does not list, so it is reported as unpriced
    /// rather than billed at a guessed rate.
    static func rates(for model: String?) -> CodexCreditRates? {
        guard let model, !model.isEmpty else { return nil }
        if let exact = table[model] { return exact }
        // A dated snapshot such as "gpt-6-astra-2026-09-01" bills like its base model.
        for key in table.keys.sorted(by: { $0.count > $1.count }) where model.hasPrefix(key + "-") {
            return table[key]
        }
        return nil
    }
}

/// The speed a request ran at, which Codex logs as the thread's `service_tier`.
/// Source: https://learn.chatgpt.com/docs/pricing (checked 2026-10-15).
enum CodexServiceTier {
    /// Fast mode draws credits at 2x the Standard rate. Codex logs it as "priority".
    static let fastCreditMultiplier = 2.0

    static func isFast(_ tier: String?) -> Bool {
        return tier == "priority" || tier == "fast"
    }

    /// Returns nil for a tier with no published multiplier, such as Ultrafast, so it is reported
    /// as unpriced rather than billed at a guessed rate. A request with no recorded tier is priced
    /// as Standard, which is what Codex runs when no tier is set.
    static func creditMultiplier(for tier: String?) -> Double? {
        switch tier {
        case nil, "default": return 1
        case let tier? where isFast(tier): return fastCreditMultiplier
        default: return nil
        }
    }
}

// MARK: - Session Records

/// One model request's token usage, read from a Codex `token_usage_record`.
/// A single message to Codex can fan out into many requests as it calls tools and the model again.
struct CodexModelRequest: Equatable {
    /// Identifies the request if a resumed session replays it into another file.
    let responseID: String?
    let timestamp: Date
    let model: String?
    /// Includes `cachedInputTokens`, matching how Codex reports it.
    let inputTokens: Int
    let cachedInputTokens: Int
    /// Includes reasoning tokens, matching how Codex reports it.
    let outputTokens: Int
    /// Nil when the session never recorded the thread's speed.
    var serviceTier: String? = nil

    var isFast: Bool {
        return CodexServiceTier.isFast(serviceTier)
    }

    /// Falls back to time and size for records written before Codex logged a response ID.
    var identity: String {
        return responseID ?? "\(timestamp.timeIntervalSince1970)|\(inputTokens)"
    }

    var totalTokens: Int {
        return inputTokens + outputTokens
    }

    var credits: Double? {
        guard
            let rates = CodexCreditRateCard.rates(for: model),
            let multiplier = CodexServiceTier.creditMultiplier(for: serviceTier)
        else { return nil }
        let uncachedInput = max(inputTokens - cachedInputTokens, 0)
        let weighted =
            Double(uncachedInput) * rates.input
            + Double(cachedInputTokens) * rates.cachedInput
            + Double(outputTokens) * rates.output
        return weighted * multiplier / 1_000_000
    }
}

struct CodexLimitWindow: Codable, Equatable {
    let usedPercent: Double
    let resetsAt: Date?
}

/// The account's 5-hour and weekly readings as Codex logged them after a response.
struct CodexLimitReading: Codable, Equatable {
    let timestamp: Date
    let windows: [CodexLimitWindow]

    /// A window stays exhausted until it resets, since usage only grows within a window.
    func isExhausted(at date: Date) -> Bool {
        return windows.contains { window in
            guard window.usedPercent >= 100 else { return false }
            guard let resetsAt = window.resetsAt else { return true }
            return resetsAt > date
        }
    }
}

/// Reads model requests and limit readings out of one session file, line by line.
/// Requests do not name their model, so the model comes from the `turn_context` that opened
/// the request's turn.
///
/// Requests do not name their speed either. Codex logs a thread's `service_tier` in a
/// `thread_settings_applied` event, but only when settings are applied, often well after the
/// thread's first requests, so a request takes the latest tier logged for its thread, or the
/// thread's first logged tier if it came before any. Codex's own logs show that first tier in
/// effect from the thread's start.
struct CodexSessionParser {
    private(set) var requests: [CodexModelRequest] = []
    private(set) var readings: [CodexLimitReading] = []
    private var modelsByTurn: [String: String] = [:]
    private var latestModel: String?
    private var tiersByThread: [String: String] = [:]
    private var latestTier: String?
    /// Indexes into `requests` of requests sent before their thread logged a tier.
    private var untieredByThread: [String: [Int]] = [:]

    mutating func consume(line: String) {
        // Every record worth reading names one of these types, so the scan skips the rest cheaply.
        guard
            line.contains("\"token_usage_record\"") || line.contains("\"token_count\"")
                || line.contains("\"turn_context\"") || line.contains("\"thread_settings_applied\"")
        else { return }
        guard
            let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
            let record = object as? [String: Any],
            let payload = record["payload"] as? [String: Any],
            let rawTimestamp = record["timestamp"] as? String,
            let timestamp = ClaudeCodeTranscripts.parseTimestamp(rawTimestamp)
        else { return }

        switch record["type"] as? String {
        case "turn_context":
            guard let model = payload["model"] as? String else { return }
            latestModel = model
            if let turnID = payload["turn_id"] as? String {
                modelsByTurn[turnID] = model
            }
        case "token_usage_record":
            guard let usage = payload["usage"] as? [String: Any] else { return }
            let model = (payload["turn_id"] as? String).flatMap { modelsByTurn[$0] } ?? latestModel
            let threadID = payload["thread_id"] as? String
            // A record without a thread ID predates per-thread logging, so the file's latest tier stands in.
            var tier = latestTier
            if let threadID {
                tier = tiersByThread[threadID]
                if tier == nil { untieredByThread[threadID, default: []].append(requests.count) }
            }
            requests.append(
                CodexModelRequest(
                    responseID: payload["response_id"] as? String,
                    timestamp: timestamp,
                    model: model,
                    inputTokens: usage["input_tokens"] as? Int ?? 0,
                    cachedInputTokens: usage["cached_input_tokens"] as? Int ?? 0,
                    outputTokens: usage["output_tokens"] as? Int ?? 0,
                    serviceTier: tier
                ))
        case "event_msg" where payload["type"] as? String == "thread_settings_applied":
            guard
                let threadID = payload["thread_id"] as? String,
                let settings = payload["thread_settings"] as? [String: Any],
                let tier = settings["service_tier"] as? String
            else { return }
            tiersByThread[threadID] = tier
            latestTier = tier
            for index in untieredByThread.removeValue(forKey: threadID) ?? [] {
                requests[index].serviceTier = tier
            }
        case "event_msg":
            guard
                payload["type"] as? String == "token_count",
                let rateLimits = payload["rate_limits"] as? [String: Any]
            else { return }
            let windows = ["primary", "secondary"].compactMap { key -> CodexLimitWindow? in
                guard
                    let window = rateLimits[key] as? [String: Any],
                    let usedPercent = window["used_percent"] as? Double
                else { return nil }
                let resetsAt = (window["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                return CodexLimitWindow(usedPercent: usedPercent, resetsAt: resetsAt)
            }
            readings.append(CodexLimitReading(timestamp: timestamp, windows: windows))
        default:
            return
        }
    }
}

// MARK: - Overage Estimate

/// One model's share of the overage estimate, at one speed.
struct CodexModelOverage: Equatable {
    let model: String
    var credits: Double
    var requests: Int
    var tokens = 0
    /// Fast and Standard spend on the same model are kept apart, since Fast costs twice as much.
    var fast = false

    func dollars(pricePerCredit: Double) -> Double {
        return credits * pricePerCredit
    }
}

/// How far back the Codex Extra row counts overage.
enum CodexOveragePeriod: String, CaseIterable {
    case month
    case week
    case day

    /// Matches Claude's Extra spend, which is a monthly total.
    static let defaultPeriod: CodexOveragePeriod = .month

    var menuTitle: String {
        switch self {
        case .month: return "Month"
        case .week: return "Week"
        case .day: return "Day"
        }
    }

    /// Follows the credit count in the Extra row, as in "1,174 credits this month".
    var rowSuffix: String {
        switch self {
        case .month: return "this month"
        case .week: return "this week"
        case .day: return "today"
        }
    }

    /// Month and day follow the local calendar. A week follows Codex's own weekly limit window,
    /// which resets on its own schedule rather than on a calendar boundary.
    func range(now: Date, weeklyWindow: CodexRateWindow?, calendar: Calendar = .current) -> (start: Date, end: Date?) {
        switch self {
        case .month, .day:
            let component: Calendar.Component = self == .month ? .month : .day
            guard let interval = calendar.dateInterval(of: component, for: now) else { return (now, nil) }
            return (interval.start, interval.end)
        case .week:
            let reported = weeklyWindow?.windowSeconds ?? 0
            let windowSeconds = reported > 0 ? reported : CodexWindowSelector.weeklyWindowSeconds
            let end = weeklyWindow?.resetsAt
            return ((end ?? now).addingTimeInterval(-windowSeconds), end)
        }
    }
}

struct CodexOverageEstimate: Equatable {
    /// When the counted period began.
    let periodStart: Date
    /// When the period ends and the estimate starts over, if known.
    let periodEnd: Date?
    var period: CodexOveragePeriod = .defaultPeriod
    var credits: Double = 0
    var overageRequests = 0
    /// Requests sent at the limit on a model the rate card does not list, left out of `credits`.
    var unpricedRequests = 0
    /// Tokens across the priced requests in `credits`.
    var tokens = 0
    /// Priced requests whose session never recorded a speed, priced as Standard.
    var unknownSpeedRequests = 0
    /// Priced spend per model and speed, most credits first.
    var models: [CodexModelOverage] = []

    func dollars(pricePerCredit: Double) -> Double {
        return credits * pricePerCredit
    }

    /// The model's share of the tokens behind the estimate, from 0 to 1.
    func tokenShare(of model: CodexModelOverage) -> Double {
        return tokens > 0 ? Double(model.tokens) / Double(tokens) : 0
    }
}

enum CodexOverageCore {
    /// OpenAI sells Codex credits to Plus and Pro in packs of 1,000 for $40.
    /// Workspace pricing depends on the agreement, so the price is a setting.
    static let defaultPricePerCredit = 0.04
    static let pricePresets: [Double] = [0.03, 0.04, 0.05]

    /// Sums the credits of requests sent since `start` while a limit was already exhausted.
    /// Limits are account-wide, so `readings` may come from any session; each request is judged by
    /// the latest reading logged before it was sent. Codex logs a reading just after each response,
    /// so the request that pushes a window to 100% is judged by the reading before it and is not
    /// counted. A request with no earlier reading cannot be judged and is not counted.
    static func estimate(
        requests: [CodexModelRequest],
        readings: [CodexLimitReading],
        since start: Date,
        until end: Date? = nil,
        period: CodexOveragePeriod = .defaultPeriod
    ) -> CodexOverageEstimate {
        var estimate = CodexOverageEstimate(periodStart: start, periodEnd: end, period: period)
        var byModel: [String: CodexModelOverage] = [:]
        for request in overageRequests(requests: requests, readings: readings, since: start) {
            guard let credits = request.credits, let model = request.model else {
                estimate.unpricedRequests += 1
                continue
            }
            estimate.credits += credits
            estimate.overageRequests += 1
            estimate.tokens += request.totalTokens
            if request.serviceTier == nil { estimate.unknownSpeedRequests += 1 }
            let key = request.isFast ? model + "|fast" : model
            byModel[key, default: CodexModelOverage(model: model, credits: 0, requests: 0, fast: request.isFast)]
                .credits += credits
            byModel[key]?.requests += 1
            byModel[key]?.tokens += request.totalTokens
        }
        estimate.models = byModel.values.sorted { first, second in
            if first.credits != second.credits { return first.credits > second.credits }
            if first.model != second.model { return first.model < second.model }
            return !first.fast && second.fast
        }
        return estimate
    }

    /// Whether any request sent in the last `window` ran on Fast. Speed is set per thread, so with
    /// threads open at both speeds this reports Fast as long as one of them is still sending.
    static func isFastActive(requests: [CodexModelRequest], now: Date, window: TimeInterval = 15 * 60) -> Bool {
        return requests.contains { $0.isFast && $0.timestamp > now.addingTimeInterval(-window) && $0.timestamp <= now }
    }

    /// The requests sent since `start` while a limit was already exhausted, priced or not, each
    /// counted once even if a resumed session replayed it into another file.
    static func overageRequests(
        requests: [CodexModelRequest], readings: [CodexLimitReading], since start: Date
    ) -> [CodexModelRequest] {
        let timeline = readings.sorted { $0.timestamp < $1.timestamp }
        var seen = Set<String>()
        return requests.filter { request in
            guard
                request.timestamp >= start,
                let reading = latestReading(before: request.timestamp, in: timeline),
                reading.isExhausted(at: request.timestamp)
            else { return false }
            return seen.insert(request.identity).inserted
        }
    }

    /// Binary search over readings sorted by time, for the last one strictly before `date`.
    private static func latestReading(before date: Date, in timeline: [CodexLimitReading]) -> CodexLimitReading? {
        var low = 0
        var high = timeline.count
        while low < high {
            let mid = (low + high) / 2
            if timeline[mid].timestamp < date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low > 0 ? timeline[low - 1] : nil
    }

    /// The counted period in local time: "Oct 1 – Oct 31, 2026" for a month, "Tue Oct 6" for a
    /// day, and "Mon Oct 5, 2:42 PM – Mon Oct 12, 2:42 PM" for Codex's weekly window.
    static func formatPeriod(_ estimate: CodexOverageEstimate, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        func format(_ date: Date, _ pattern: String) -> String {
            formatter.dateFormat = pattern
            return formatter.string(from: date)
        }

        switch estimate.period {
        case .day:
            return format(estimate.periodStart, "EEE MMM d")
        case .month:
            guard let end = estimate.periodEnd else { return "Since " + format(estimate.periodStart, "MMM d, yyyy") }
            // The period ends at midnight on the 1st, so the last day shown is the one before it.
            let lastDay = end.addingTimeInterval(-1)
            return format(estimate.periodStart, "MMM d") + " – " + format(lastDay, "MMM d, yyyy")
        case .week:
            let start = format(estimate.periodStart, "EEE MMM d, h:mm a")
            guard let end = estimate.periodEnd else { return "Since \(start)" }
            return "\(start) – " + format(end, "EEE MMM d, h:mm a")
        }
    }

    /// Accepts "0.04", "$0.04", or a comma decimal such as "0,04".
    static func parsePricePerCredit(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let price = Double(cleaned), price.isFinite, price > 0, price <= 10 else { return nil }
        return price
    }

    /// Shows at least cents and up to four decimals, so a custom price like $0.035 survives.
    static func formatPrice(_ price: Double) -> String {
        var digits = String(format: "%.4f", price)
        while digits.hasSuffix("0"), let dot = digits.firstIndex(of: "."), digits.distance(from: dot, to: digits.endIndex) > 3 {
            digits.removeLast()
        }
        return "$" + digits
    }

    static func formatDollars(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    /// Whole percent, with "<1%" and ">99%" so a share never reads as none or all when it is not.
    static func formatShare(_ share: Double) -> String {
        if share > 0 && share <= 0.005 { return "<1%" }
        if share < 1 && share >= 0.995 { return ">99%" }
        return String(format: "%.0f%%", share * 100)
    }

    static func formatCredits(_ credits: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = credits < 10 ? 1 : 0
        let number = formatter.string(from: NSNumber(value: credits)) ?? String(format: "%.0f", credits)
        return "\(number) credits"
    }
}
