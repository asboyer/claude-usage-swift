import Foundation

// MARK: - Codex Rate Limit Windows

/// A Codex rate limit window normalized across the sources that report it.
struct CodexRateWindow: Equatable {
    let usedPercent: Double
    let windowSeconds: TimeInterval
    let resetsAt: Date?
}

enum CodexWindowSelector {
    static let weeklyWindowSeconds: TimeInterval = 7 * 86400
    static let fiveHourWindowSeconds: TimeInterval = 5 * 3600
    private static let weeklyMatchTolerance: TimeInterval = 12 * 3600
    private static let fiveHourMatchTolerance: TimeInterval = 1800

    /// Picks the window that tracks Codex weekly usage.
    /// Plans report it as either the primary or secondary window, so windows are matched by
    /// length rather than position, falling back to the longest window available.
    static func selectWeekly(primary: CodexRateWindow?, secondary: CodexRateWindow?) -> CodexRateWindow? {
        let windows = [primary, secondary].compactMap { $0 }
        guard !windows.isEmpty else { return nil }

        if let weekly = windows.first(where: { abs($0.windowSeconds - weeklyWindowSeconds) <= weeklyMatchTolerance }) {
            return weekly
        }
        return windows.max { $0.windowSeconds < $1.windowSeconds }
    }

    /// Picks the window that tracks Codex session usage.
    /// Unlike the weekly window there is no fallback: a plan that only reports a long window
    /// has no session limit to show.
    static func selectFiveHour(primary: CodexRateWindow?, secondary: CodexRateWindow?) -> CodexRateWindow? {
        let windows = [primary, secondary].compactMap { $0 }
        return windows.first { abs($0.windowSeconds - fiveHourWindowSeconds) <= fiveHourMatchTolerance }
    }
}

// MARK: - Menu Bar Ownership

/// Which provider's percentage the status item currently displays.
/// Declaration order breaks ties between providers that moved by the same amount.
enum UsageProvider: String, Codable, CaseIterable {
    case claude
    case codex
    case cursor
}

struct MenuBarOwnership: Equatable {
    var provider: UsageProvider
    var lastUtilizations: [UsageProvider: Double]

    static let claudeDefault = MenuBarOwnership(provider: .claude, lastUtilizations: [:])
}

enum MenuBarOwnershipResolver {
    /// Hands the status item to whichever provider most recently consumed usage.
    /// Utilization drops mean a limit window reset, so they never transfer ownership.
    static func resolve(
        current: MenuBarOwnership,
        utilizations: [UsageProvider: Double?]
    ) -> MenuBarOwnership {
        var updated = current
        let reported = utilizations.compactMapValues { $0 }
        guard !reported.isEmpty else { return updated }

        var increases: [UsageProvider: Double] = [:]
        for (provider, utilization) in reported {
            if let previous = current.lastUtilizations[provider], utilization > previous {
                increases[provider] = utilization - previous
            }
            updated.lastUtilizations[provider] = utilization
        }

        if let claimant = providerWithLargestIncrease(increases) {
            updated.provider = claimant
            return updated
        }

        // A provider without data cannot own the status item.
        if reported[updated.provider] == nil {
            updated.provider = UsageProvider.allCases.first { reported[$0] != nil } ?? updated.provider
        }
        return updated
    }

    private static func providerWithLargestIncrease(_ increases: [UsageProvider: Double]) -> UsageProvider? {
        return UsageProvider.allCases
            .filter { increases[$0] != nil }
            .max { (increases[$0] ?? 0) < (increases[$1] ?? 0) }
    }
}
