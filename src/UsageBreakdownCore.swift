import Foundation

// MARK: - Model Pricing

/// Published per-million-token rates for one model, used to weight how much a request
/// contributed to plan limits. Limits are not billed in dollars, so these rates are only a
/// proxy: they keep an expensive model's tokens from counting the same as a cheap model's.
struct ModelRates: Equatable {
    let input: Double
    let cacheWrite5m: Double
    let cacheWrite1h: Double
    let cacheRead: Double
    let output: Double
}

enum ClaudeModelRates {
    /// Opus-tier rates stand in for a model the table does not know yet.
    static let fallback = ModelRates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.5, output: 25)

    /// Cache writes bill at 1.25x input for the 5-minute TTL and 2x for the 1-hour TTL.
    /// Cache reads bill at 0.1x input, except on Fable 5.1, which reads at $0.25/MTok.
    static let table: [String: ModelRates] = [
        "claude-fable-5-1": ModelRates(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 0.25, output: 50),
        "claude-mythos-5-1": ModelRates(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 1, output: 50),
        "claude-fable-5": ModelRates(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 1, output: 50),
        "claude-mythos-5": ModelRates(input: 10, cacheWrite5m: 12.5, cacheWrite1h: 20, cacheRead: 1, output: 50),
        "claude-opus-5": ModelRates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.5, output: 25),
        "claude-opus-4-8": ModelRates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.5, output: 25),
        "claude-opus-4-7": ModelRates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.5, output: 25),
        "claude-opus-4-6": ModelRates(input: 5, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.5, output: 25),
        "claude-sonnet-5": ModelRates(input: 2, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.2, output: 10),
        "claude-sonnet-4-6": ModelRates(input: 3, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.3, output: 15),
        "claude-haiku-4-5": ModelRates(input: 1, cacheWrite5m: 1.25, cacheWrite1h: 2, cacheRead: 0.1, output: 5),
    ]

    /// Families are matched last so an unreleased point release still lands in the right tier.
    private static let families: [(marker: String, key: String)] = [
        ("fable", "claude-fable-5-1"), ("mythos", "claude-mythos-5-1"), ("opus", "claude-opus-5"),
        ("sonnet", "claude-sonnet-5"), ("haiku", "claude-haiku-4-5"),
    ]

    static func rates(for model: String?) -> ModelRates {
        guard let model, !model.isEmpty else { return fallback }
        // Context-window suffixes such as "claude-opus-5[1m]" name the same tier.
        let base = String(model.prefix(while: { $0 != "[" }))
        if let exact = table[base] { return exact }
        for key in table.keys.sorted(by: { $0.count > $1.count }) where base.hasPrefix(key) {
            return table[key] ?? fallback
        }
        for family in families where base.contains(family.marker) {
            return table[family.key] ?? fallback
        }
        return fallback
    }
}

// MARK: - Transcript Records

/// One assistant API request read out of a local Claude Code transcript.
struct TranscriptRequest: Equatable {
    let sessionID: String
    let timestamp: Date
    let model: String?
    let inputTokens: Int
    let cacheWrite5mTokens: Int
    let cacheWrite1hTokens: Int
    let cacheReadTokens: Int
    let outputTokens: Int
    let isSubagent: Bool
    let agent: String?
    let skill: String?

    /// How large the prompt was for this request, cached or not.
    var contextTokens: Int {
        return inputTokens + cacheWrite5mTokens + cacheWrite1hTokens + cacheReadTokens
    }

    /// Weighted cost of the request, in dollars, used only to compare requests against each other.
    var weightedCost: Double {
        let rates = ClaudeModelRates.rates(for: model)
        let weighted =
            Double(inputTokens) * rates.input
            + Double(cacheWrite5mTokens) * rates.cacheWrite5m
            + Double(cacheWrite1hTokens) * rates.cacheWrite1h
            + Double(cacheReadTokens) * rates.cacheRead
            + Double(outputTokens) * rates.output
        return weighted / 1_000_000
    }

    /// Subagent work is grouped under the skill that spawned it when there is one, because a
    /// skill's subagents are what the reader can act on, not the generic agent type behind them.
    var subagentGroup: String {
        return skill ?? agent ?? "unattributed"
    }
}

// MARK: - Breakdown

/// One independent characteristic of recent usage. Shares do not sum to 100% by design.
struct UsageSignal: Equatable {
    let share: Double
    let headline: String
    let advice: String
}

struct UsageShare: Equatable {
    let label: String
    let share: Double
}

struct UsageBreakdown: Equatable {
    let windowHours: Int
    let requestCount: Int
    let sessionCount: Int
    let signals: [UsageSignal]
    let skills: [UsageShare]
    let subagents: [UsageShare]

    static func empty(windowHours: Int) -> UsageBreakdown {
        return UsageBreakdown(
            windowHours: windowHours, requestCount: 0, sessionCount: 0,
            signals: [], skills: [], subagents: []
        )
    }

    var isEmpty: Bool { return requestCount == 0 }
}

enum UsageBreakdownBuilder {
    /// A session counts as subagent-heavy once subagents run at least half of its cost.
    static let subagentHeavyThreshold = 0.5
    static let longContextTokens = 150_000
    static let longSessionSeconds: TimeInterval = 8 * 3600
    /// Below this a signal is noise rather than something worth changing.
    static let minimumSignalShare = 0.05
    static let minimumRowShare = 0.005
    static let maximumRows = 6

    static func build(from requests: [TranscriptRequest], windowHours: Int) -> UsageBreakdown {
        let total = requests.reduce(0.0) { $0 + $1.weightedCost }
        guard total > 0 else { return .empty(windowHours: windowHours) }

        var sessionCost: [String: Double] = [:]
        var sessionSubagentCost: [String: Double] = [:]
        var sessionFirst: [String: Date] = [:]
        var sessionLast: [String: Date] = [:]
        var longContextCost = 0.0
        var skillCost: [String: Double] = [:]
        var subagentCost: [String: Double] = [:]

        for request in requests {
            let cost = request.weightedCost
            let session = request.sessionID
            sessionCost[session, default: 0] += cost
            if request.isSubagent {
                sessionSubagentCost[session, default: 0] += cost
                subagentCost[request.subagentGroup, default: 0] += cost
            } else if let skill = request.skill {
                skillCost[skill, default: 0] += cost
            }
            if request.contextTokens > longContextTokens {
                longContextCost += cost
            }
            sessionFirst[session] = min(sessionFirst[session] ?? request.timestamp, request.timestamp)
            sessionLast[session] = max(sessionLast[session] ?? request.timestamp, request.timestamp)
        }

        var subagentHeavyCost = 0.0
        var longSessionCost = 0.0
        for (session, cost) in sessionCost where cost > 0 {
            if (sessionSubagentCost[session] ?? 0) / cost >= subagentHeavyThreshold {
                subagentHeavyCost += cost
            }
            if let first = sessionFirst[session], let last = sessionLast[session],
                last.timeIntervalSince(first) >= longSessionSeconds
            {
                longSessionCost += cost
            }
        }

        var signals: [UsageSignal] = [
            UsageSignal(
                share: subagentHeavyCost / total,
                headline: "of your usage came from subagent-heavy sessions",
                advice: "Each subagent runs its own requests. Be deliberate about spawning them — and consider "
                    + "configuring a cheaper model for simpler subagents."
            ),
            UsageSignal(
                share: longContextCost / total,
                headline: "of your usage was at >150k context",
                advice: "Longer sessions are more expensive even when cached. /compact mid-task, /clear when "
                    + "switching to new tasks."
            ),
            UsageSignal(
                share: longSessionCost / total,
                headline: "of your usage came from sessions active for 8+ hours",
                advice: "These are often background/loop sessions. Continuous usage can add up quickly so make "
                    + "sure it is intentional."
            ),
        ]
        if let top = subagentCost.max(by: { $0.value < $1.value }) {
            signals.append(
                UsageSignal(
                    share: top.value / total,
                    headline: "of your usage came from subagents under \"\(top.key)\"",
                    advice: "If this runs frequently, consider configuring its subagents with a cheaper model or "
                        + "tightening their prompts."
                )
            )
        }

        return UsageBreakdown(
            windowHours: windowHours,
            requestCount: requests.count,
            sessionCount: sessionCost.count,
            signals: signals.filter { $0.share >= minimumSignalShare }.sorted { $0.share > $1.share },
            skills: shares(from: skillCost, total: total),
            subagents: shares(from: subagentCost, total: total)
        )
    }

    private static func shares(from costs: [String: Double], total: Double) -> [UsageShare] {
        var rows: [UsageShare] = []
        for (label, cost) in costs {
            let share = cost / total
            if share >= minimumRowShare {
                rows.append(UsageShare(label: label, share: share))
            }
        }
        rows.sort { left, right in
            left.share == right.share ? left.label < right.label : left.share > right.share
        }
        return Array(rows.prefix(maximumRows))
    }
}
