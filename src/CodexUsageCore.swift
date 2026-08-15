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
    private static let weeklyMatchTolerance: TimeInterval = 12 * 3600

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
}

// MARK: - Menu Bar Ownership

/// Which provider's percentage the status item currently displays.
enum UsageProvider: String, Codable {
    case claude
    case codex
}

struct MenuBarOwnership: Equatable {
    var provider: UsageProvider
    var lastClaudeUtilization: Double?
    var lastCodexUtilization: Double?

    static let claudeDefault = MenuBarOwnership(
        provider: .claude,
        lastClaudeUtilization: nil,
        lastCodexUtilization: nil
    )
}

enum MenuBarOwnershipResolver {
    /// Hands the status item to whichever provider most recently consumed usage.
    /// Utilization drops mean a limit window reset, so they never transfer ownership.
    static func resolve(
        current: MenuBarOwnership,
        claudeUtilization: Double?,
        codexUtilization: Double?
    ) -> MenuBarOwnership {
        var updated = current
        let claudeIncrease = increase(from: current.lastClaudeUtilization, to: claudeUtilization)
        let codexIncrease = increase(from: current.lastCodexUtilization, to: codexUtilization)

        if let claudeUtilization {
            updated.lastClaudeUtilization = claudeUtilization
        }
        if let codexUtilization {
            updated.lastCodexUtilization = codexUtilization
        }

        // A provider without data cannot own the status item.
        if claudeUtilization == nil, codexUtilization != nil {
            updated.provider = .codex
            return updated
        }
        if codexUtilization == nil, claudeUtilization != nil {
            updated.provider = .claude
            return updated
        }

        switch (claudeIncrease, codexIncrease) {
        case (let claudeDelta?, let codexDelta?):
            updated.provider = codexDelta > claudeDelta ? .codex : .claude
        case (_?, nil):
            updated.provider = .claude
        case (nil, _?):
            updated.provider = .codex
        case (nil, nil):
            break
        }

        return updated
    }

    private static func increase(from previous: Double?, to current: Double?) -> Double? {
        guard let previous, let current, current > previous else { return nil }
        return current - previous
    }
}
