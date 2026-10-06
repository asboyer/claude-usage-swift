import Foundation

// MARK: - Ledger

enum SpendProvider: String, CaseIterable, Codable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

/// One model's spend on one day, either what was billed past the plan or all usage priced at
/// published rates. Codex is kept in credits, so a change to the credit price reprices all of history.
struct SpendEntry: Codable, Equatable {
    /// Tokens behind the spend.
    var tokens = 0
    var dollars = 0.0
    var credits = 0.0

    mutating func add(_ other: SpendEntry) {
        tokens += other.tokens
        dollars += other.dollars
        credits += other.credits
    }
}

typealias SpendDays = [String: [String: [String: SpendEntry]]]

/// A rise in Claude's monthly Extra total between two readings. `start` is nil when the earlier
/// reading is unknown, as for spend billed before the app first saw the month.
struct ClaudeExtraIncrease: Codable, Equatable {
    let start: Date?
    let end: Date
    let dollars: Double
}

struct ClaudeExtraReading: Codable, Equatable {
    let at: Date
    let dollars: Double
    let month: String
}

/// Daily extra spend kept by the app itself. Claude Code deletes transcripts after 30 days, and
/// the Claude API reports only the running monthly total, so history survives only here.
struct SpendLedger: Codable, Equatable {
    /// "yyyy-MM-dd" in local time -> provider -> model -> extra spend.
    var days: SpendDays = [:]
    /// The same shape for all usage, extra included, priced at API or credit rates.
    var usageDays: SpendDays = [:]
    /// Claude increases not yet split across models; the next scan attributes them.
    var pendingClaudeExtra: [ClaudeExtraIncrease] = []
    var lastClaudeExtra: ClaudeExtraReading?
    /// When the app first read Claude's Extra total; Claude history starts here.
    var claudeTrackedSince: Date?
    var lastScan: Date?

    /// Keeps, per day and model, whichever Codex entry covers more tokens. A scan only ever sees
    /// fewer tokens for a day than before once older session files have been deleted.
    mutating func mergeCodex(days scanned: SpendDays) {
        let key = SpendProvider.codex.rawValue
        for (day, providers) in scanned {
            for (model, entry) in providers[key] ?? [:] {
                let stored = days[day]?[key]?[model]
                if stored == nil || entry.tokens >= stored!.tokens {
                    days[day, default: [:]][key, default: [:]][model] = entry
                }
            }
        }
    }

    /// Keeps, per day and model, whichever usage entry covers more tokens, for the same reason.
    mutating func mergeUsage(days scanned: SpendDays) {
        for (day, providers) in scanned {
            for (provider, models) in providers {
                for (model, entry) in models {
                    let stored = usageDays[day]?[provider]?[model]
                    if stored == nil || entry.tokens >= stored!.tokens {
                        usageDays[day, default: [:]][provider, default: [:]][model] = entry
                    }
                }
            }
        }
    }

    /// Claude attributions are final once made, so they add rather than replace.
    mutating func add(days attributed: SpendDays) {
        for (day, providers) in attributed {
            for (provider, models) in providers {
                for (model, entry) in models {
                    days[day, default: [:]][provider, default: [:]][model, default: SpendEntry()].add(entry)
                }
            }
        }
    }

    /// Turns a new reading of Claude's monthly Extra total into an increase. The total resets each
    /// month, so a reading in a new month, or one below the last, counts from zero.
    mutating func recordClaudeExtra(dollars: Double, at now: Date, calendar: Calendar = .current) {
        let month = SpendLedgerBuilder.monthKey(now, calendar: calendar)
        let previous = lastClaudeExtra
        claudeTrackedSince = claudeTrackedSince ?? now
        lastClaudeExtra = ClaudeExtraReading(at: now, dollars: dollars, month: month)
        guard let previous, previous.month == month else {
            // Without a reading near the reset, there is no telling when this month's spend happened.
            let recent = previous.map { now.timeIntervalSince($0.at) < 3600 } ?? false
            let start = recent ? calendar.dateInterval(of: .month, for: now)?.start : nil
            if dollars > 0 {
                pendingClaudeExtra.append(ClaudeExtraIncrease(start: start, end: now, dollars: dollars))
            }
            return
        }
        // A drop within the month key is a reset that doesn't follow the local calendar month
        // (UTC or billing date), so everything since the last reading is new spend.
        let increase = dollars < previous.dollars ? dollars : dollars - previous.dollars
        if increase > 0.005 {
            pendingClaudeExtra.append(ClaudeExtraIncrease(start: previous.at, end: now, dollars: increase))
        }
    }
}

enum SpendLedgerBuilder {
    /// Model name for Claude spend the app cannot place on a model.
    static let beforeTracking = "Before tracking"

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    private static func add(
        _ days: inout SpendDays, _ date: Date, _ provider: SpendProvider, _ model: String,
        calendar: Calendar, _ entry: SpendEntry
    ) {
        days[dayKey(date, calendar: calendar), default: [:]][provider.rawValue, default: [:]][
            model, default: SpendEntry()
        ].add(entry)
    }

    /// Every request per day and model, priced at API rates for Claude and credit rates for Codex.
    /// Codex requests on models without a credit rate are left out.
    static func usageDays(
        claude: [TranscriptRequest], codex: [CodexModelRequest], calendar: Calendar = .current
    ) -> SpendDays {
        var days: SpendDays = [:]
        for request in claude {
            add(
                &days, request.timestamp, .claude, displayModel(request.model), calendar: calendar,
                SpendEntry(tokens: request.contextTokens + request.outputTokens, dollars: request.weightedCost))
        }
        var seen = Set<String>()
        for request in codex where seen.insert(request.identity).inserted {
            guard let credits = request.credits, let model = request.model else { continue }
            add(
                &days, request.timestamp, .codex, model, calendar: calendar,
                SpendEntry(tokens: request.totalTokens, credits: credits))
        }
        return days
    }

    /// Codex overage per day and model. Requests on models without a credit rate are left out.
    static func codexDays(
        requests: [CodexModelRequest], readings: [CodexLimitReading], calendar: Calendar = .current
    ) -> SpendDays {
        var days: SpendDays = [:]
        for request in CodexOverageCore.overageRequests(requests: requests, readings: readings, since: .distantPast) {
            guard let credits = request.credits, let model = request.model else { continue }
            add(
                &days, request.timestamp, .codex, model, calendar: calendar,
                SpendEntry(tokens: request.totalTokens, credits: credits))
        }
        return days
    }

    /// Splits each Claude increase across the requests sent while it accrued, by their cost at API
    /// rates, which is how Extra usage is billed. An increase with no known start or no requests
    /// in its window lands on its end day as "Before tracking".
    static func claudeDays(
        increases: [ClaudeExtraIncrease], requests: [TranscriptRequest], calendar: Calendar = .current
    ) -> SpendDays {
        var days: SpendDays = [:]
        let sorted = requests.sorted { $0.timestamp < $1.timestamp }
        for increase in increases {
            let window =
                increase.start.map { start in
                    sorted.filter { $0.timestamp > start && $0.timestamp <= increase.end }
                } ?? []
            let cost = window.reduce(0) { $0 + $1.weightedCost }
            guard cost > 0 else {
                add(
                    &days, increase.end, .claude, beforeTracking, calendar: calendar,
                    SpendEntry(dollars: increase.dollars))
                continue
            }
            for request in window {
                let fraction = request.weightedCost / cost
                let tokens = Double(request.contextTokens + request.outputTokens) * fraction
                add(
                    &days, request.timestamp, .claude, displayModel(request.model), calendar: calendar,
                    SpendEntry(tokens: Int(tokens.rounded()), dollars: increase.dollars * fraction))
            }
        }
        return days
    }

    /// "claude-opus-5[1m]" and "claude-opus-5-20260901" are one model on the bill.
    static func displayModel(_ model: String?) -> String {
        guard let model, !model.isEmpty else { return "unknown" }
        var base = String(model.prefix(while: { $0 != "[" }))
        if let range = base.range(of: #"-\d{8}$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        return base
    }
}

// MARK: - Periods

enum SpendKind: String, CaseIterable {
    /// Billed past the plans: Claude Extra usage and Codex overage.
    case extra
    /// All usage priced at published rates, extra included.
    case usage
}

enum SpendGranularity: String, CaseIterable {
    case week
    case month

    var component: Calendar.Component {
        return self == .week ? .weekOfYear : .month
    }
}

struct SpendModelRow: Equatable {
    let model: String
    let dollars: Double
    /// The model's share of the tokens behind its provider's extra spend, from 0 to 1.
    let tokenShare: Double
}

struct SpendProviderTotal: Equatable {
    let provider: SpendProvider
    let dollars: Double
    /// The part of `dollars` billed past the plan; equal to it for extra spend.
    let extraDollars: Double
    /// Most expensive first.
    let models: [SpendModelRow]
}

struct SpendPeriod: Equatable {
    let start: Date
    let end: Date
    /// Only providers with extra spend in the period.
    let providers: [SpendProviderTotal]

    var dollars: Double {
        return providers.reduce(0) { $0 + $1.dollars }
    }

    var extraDollars: Double {
        return providers.reduce(0) { $0 + $1.extraDollars }
    }

    func provider(_ provider: SpendProvider) -> SpendProviderTotal? {
        return providers.first { $0.provider == provider }
    }
}

enum SpendHistoryCore {
    /// The last `count` periods ending with the current one, oldest first.
    static func periods(
        from ledger: SpendLedger,
        kind: SpendKind = .extra,
        granularity: SpendGranularity,
        count: Int,
        pricePerCredit: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SpendPeriod] {
        guard let current = calendar.dateInterval(of: granularity.component, for: now) else { return [] }
        var intervals: [DateInterval] = [current]
        while intervals.count < count,
            let previous = calendar.dateInterval(
                of: granularity.component, for: intervals[0].start.addingTimeInterval(-1))
        {
            intervals.insert(previous, at: 0)
        }

        func bucket(_ source: SpendDays) -> [[String: [String: SpendEntry]]] {
            var buckets = Array(repeating: [String: [String: SpendEntry]](), count: intervals.count)
            for (day, providers) in source {
                guard
                    let date = parseDay(day, calendar: calendar),
                    let index = intervals.firstIndex(where: { $0.start <= date && date < $0.end })
                else { continue }
                for (provider, models) in providers {
                    for (model, entry) in models {
                        buckets[index][provider, default: [:]][model, default: SpendEntry()].add(entry)
                    }
                }
            }
            return buckets
        }
        let extra = bucket(ledger.days)
        let shown = kind == .extra ? extra : bucket(ledger.usageDays)

        return intervals.enumerated().map { index, interval in
            let providers = SpendProvider.allCases.compactMap { provider -> SpendProviderTotal? in
                let key = provider.rawValue
                let extraTotal = providerTotal(
                    provider, models: extra[index][key] ?? [:], extraDollars: 0, pricePerCredit: pricePerCredit)
                let total = providerTotal(
                    provider, models: shown[index][key] ?? [:], extraDollars: extraTotal.dollars,
                    pricePerCredit: pricePerCredit)
                return total.dollars > 0 ? total : nil
            }
            return SpendPeriod(start: interval.start, end: interval.end, providers: providers)
        }
    }

    private static func providerTotal(
        _ provider: SpendProvider, models: [String: SpendEntry], extraDollars: Double, pricePerCredit: Double
    ) -> SpendProviderTotal {
        let tokens = models.values.reduce(0) { $0 + $1.tokens }
        var rows: [SpendModelRow] = []
        for (model, entry) in models {
            let dollars = provider == .codex ? entry.credits * pricePerCredit : entry.dollars
            guard dollars > 0 else { continue }
            let share = tokens > 0 ? Double(entry.tokens) / Double(tokens) : 0
            rows.append(SpendModelRow(model: model, dollars: dollars, tokenShare: share))
        }
        rows.sort { $0.dollars != $1.dollars ? $0.dollars > $1.dollars : $0.model < $1.model }
        return SpendProviderTotal(
            provider: provider, dollars: rows.reduce(0) { $0 + $1.dollars }, extraDollars: extraDollars,
            models: rows)
    }

    static func parseDay(_ day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
