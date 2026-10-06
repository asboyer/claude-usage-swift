import Foundation

// MARK: - Ledger

enum SpendProvider: String, CaseIterable, Codable {
    case claude
    case codex
    case opencode

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "Opencode"
        }
    }
}

/// One model's spend on one day billed past the plan. Codex is kept in credits, so a change to the credit price reprices all of history.
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
    /// Claude increases not yet split across models; the next scan attributes them.
    var pendingClaudeExtra: [ClaudeExtraIncrease] = []
    var lastClaudeExtra: ClaudeExtraReading?
    /// A reading below `lastClaudeExtra`, kept until the next one shows whether the total reset.
    var claudeExtraDip: ClaudeExtraReading?
    /// When the app first read Claude's Extra total; Claude history starts here.
    var claudeTrackedSince: Date?
    var lastScan: Date?
    /// Kept apart from `lastScan`: a provider switched on later needs its first scan in full.
    var lastCodexScan: Date?

    /// Keeps, per day and model, whichever entry of `provider` covers more tokens. A scan only ever
    /// sees fewer tokens for a day than before once older session files have been deleted, or when
    /// it read only the files touched since the last scan.
    mutating func merge(_ provider: SpendProvider, days scanned: SpendDays) {
        let key = provider.rawValue
        for (day, providers) in scanned {
            for (model, entry) in providers[key] ?? [:] {
                let stored = days[day]?[key]?[model]
                if stored == nil || entry.tokens >= stored!.tokens {
                    days[day, default: [:]][key, default: [:]][model] = entry
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

    /// Turns a new reading of Claude's monthly Extra total into an increase over the last one. The
    /// API resets the total on its own schedule (UTC or billing date), so the local month alone
    /// never marks a reset: a drop does, once the next reading confirms it.
    mutating func recordClaudeExtra(dollars: Double, at now: Date, calendar: Calendar = .current) {
        let reading = ClaudeExtraReading(at: now, dollars: dollars, month: SpendLedgerBuilder.monthKey(now, calendar: calendar))
        claudeTrackedSince = claudeTrackedSince ?? now
        guard let previous = lastClaudeExtra else {
            lastClaudeExtra = reading
            // Spend billed before the first reading has no known window.
            if dollars > 0 { pendingClaudeExtra.append(ClaudeExtraIncrease(start: nil, end: now, dollars: dollars)) }
            return
        }
        // Readings more than 36 hours apart across a month boundary straddle a reset in any time zone.
        if previous.month != reading.month && now.timeIntervalSince(previous.at) > 36 * 3600 {
            lastClaudeExtra = reading
            claudeExtraDip = nil
            if dollars > 0 { pendingClaudeExtra.append(ClaudeExtraIncrease(start: nil, end: now, dollars: dollars)) }
            return
        }
        if dollars >= previous.dollars {
            // A dip that the total climbs back from was a bad reading, not a reset.
            claudeExtraDip = nil
            lastClaudeExtra = reading
            appendClaudeExtra(start: previous.at, end: now, dollars: dollars - previous.dollars)
            return
        }
        guard let dip = claudeExtraDip else {
            // Held back until the next reading, so one low response cannot recount the whole month.
            claudeExtraDip = reading
            return
        }
        // Two readings below the last good one: the total reset, and all of it since then is new spend.
        appendClaudeExtra(start: previous.at, end: dip.at, dollars: dip.dollars)
        appendClaudeExtra(start: dip.at, end: now, dollars: dollars - dip.dollars)
        claudeExtraDip = nil
        lastClaudeExtra = reading
    }

    private mutating func appendClaudeExtra(start: Date, end: Date, dollars: Double) {
        if dollars > 0.005 {
            pendingClaudeExtra.append(ClaudeExtraIncrease(start: start, end: end, dollars: dollars))
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

    /// Opencode spend per day and model. Opencode bills per token, so all of its cost is extra.
    static func opencodeDays(requests: [OpencodeRequestCost], calendar: Calendar = .current) -> SpendDays {
        var days: SpendDays = [:]
        for request in requests where request.costUSD > 0 {
            add(
                &days, request.timestamp, .opencode, request.model, calendar: calendar,
                SpendEntry(tokens: request.tokens, dollars: request.costUSD))
        }
        return days
    }

    /// Where an incremental Codex rescan starts reading. A request on a day at or after the cutoff can
    /// only be in a file modified since then, so those days come back complete; the day before is
    /// included so a request still finds the limit reading logged just before it.
    static func codexRescanCutoff(lastScan: Date, calendar: Calendar = .current) -> Date {
        return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: lastScan)) ?? lastScan
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

    func provider(_ provider: SpendProvider) -> SpendProviderTotal? {
        return providers.first { $0.provider == provider }
    }
}

enum SpendHistoryCore {
    /// The last `count` periods ending with the current one, oldest first.
    static func periods(
        from ledger: SpendLedger,
        providers shownProviders: Set<SpendProvider> = Set(SpendProvider.allCases),
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
        let buckets = bucket(ledger.days)

        return intervals.enumerated().map { index, interval in
            let providers = SpendProvider.allCases.filter(shownProviders.contains).compactMap {
                provider -> SpendProviderTotal? in
                let total = providerTotal(
                    provider, models: buckets[index][provider.rawValue] ?? [:], pricePerCredit: pricePerCredit)
                return total.dollars > 0 ? total : nil
            }
            return SpendPeriod(start: interval.start, end: interval.end, providers: providers)
        }
    }

    private static func providerTotal(
        _ provider: SpendProvider, models: [String: SpendEntry], pricePerCredit: Double
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
            provider: provider, dollars: rows.reduce(0) { $0 + $1.dollars }, models: rows)
    }

    static func parseDay(_ day: String, calendar: Calendar) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
