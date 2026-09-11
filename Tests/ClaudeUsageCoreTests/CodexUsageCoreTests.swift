import Foundation
import Testing

@testable import ClaudeUsageCore

struct CodexUsageCoreTests {
    private func window(usedPercent: Double, windowSeconds: TimeInterval) -> CodexRateWindow {
        return CodexRateWindow(usedPercent: usedPercent, windowSeconds: windowSeconds, resetsAt: nil)
    }

    // MARK: - Weekly Window Selection

    @Test func selectWeeklyPicksPrimaryWhenItIsTheSevenDayWindow() {
        let primary = window(usedPercent: 12, windowSeconds: 604_800)
        let selected = CodexWindowSelector.selectWeekly(primary: primary, secondary: nil)
        #expect(selected == primary)
    }

    @Test func selectWeeklyPicksSecondaryWhenPrimaryIsTheSessionWindow() {
        let primary = window(usedPercent: 40, windowSeconds: 5 * 3600)
        let secondary = window(usedPercent: 12, windowSeconds: 604_800)
        let selected = CodexWindowSelector.selectWeekly(primary: primary, secondary: secondary)
        #expect(selected == secondary)
    }

    @Test func selectWeeklyFallsBackToLongestWindowWhenNoneIsSevenDays() {
        let primary = window(usedPercent: 40, windowSeconds: 5 * 3600)
        let secondary = window(usedPercent: 12, windowSeconds: 30 * 86400)
        let selected = CodexWindowSelector.selectWeekly(primary: primary, secondary: secondary)
        #expect(selected == secondary)
    }

    @Test func selectWeeklyReturnsNilWithoutWindows() {
        #expect(CodexWindowSelector.selectWeekly(primary: nil, secondary: nil) == nil)
    }

    // MARK: - Five Hour Window Selection

    @Test func selectFiveHourPicksTheSessionWindow() {
        let primary = window(usedPercent: 99, windowSeconds: 18000)
        let secondary = window(usedPercent: 62, windowSeconds: 604_800)
        let selected = CodexWindowSelector.selectFiveHour(primary: primary, secondary: secondary)
        #expect(selected == primary)
    }

    @Test func selectFiveHourPicksSecondaryWhenPrimaryIsWeekly() {
        let primary = window(usedPercent: 62, windowSeconds: 604_800)
        let secondary = window(usedPercent: 99, windowSeconds: 18000)
        let selected = CodexWindowSelector.selectFiveHour(primary: primary, secondary: secondary)
        #expect(selected == secondary)
    }

    @Test func selectFiveHourReturnsNilWhenNoSessionWindowIsReported() {
        let primary = window(usedPercent: 62, windowSeconds: 604_800)
        let secondary = window(usedPercent: 20, windowSeconds: 30 * 86400)
        #expect(CodexWindowSelector.selectFiveHour(primary: primary, secondary: secondary) == nil)
    }

    // MARK: - Menu Bar Ownership

    @Test func ownershipMovesToCodexWhenCodexIncreases() {
        let current = MenuBarOwnership(provider: .claude, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 40, .codex: 14]
        )

        #expect(updated.provider == .codex)
        #expect(updated.lastUtilizations[.codex] == 14)
        #expect(updated.lastUtilizations[.claude] == 40)
    }

    @Test func ownershipMovesToClaudeWhenClaudeIncreases() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 46, .codex: 10]
        )

        #expect(updated.provider == .claude)
    }

    @Test func ownershipMovesToCursorWhenCursorIncreases() {
        let current = MenuBarOwnership(
            provider: .claude,
            lastUtilizations: [.claude: 40, .codex: 10, .cursor: 2]
        )
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 40, .codex: 10, .cursor: 6]
        )

        #expect(updated.provider == .cursor)
        #expect(updated.lastUtilizations[.cursor] == 6)
    }

    @Test func ownershipPrefersLargerIncreaseWhenAllMoved() {
        let current = MenuBarOwnership(
            provider: .claude,
            lastUtilizations: [.claude: 40, .codex: 10, .cursor: 2]
        )
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 41, .codex: 18, .cursor: 3]
        )

        #expect(updated.provider == .codex)
    }

    @Test func ownershipIsUnchangedWhenNeitherIncreases() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 40, .codex: 10]
        )

        #expect(updated.provider == .codex)
    }

    @Test func limitResetDoesNotTransferOwnership() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 90])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 5, .codex: 0]
        )

        #expect(updated.provider == .codex)
        #expect(updated.lastUtilizations[.claude] == 5)
        #expect(updated.lastUtilizations[.codex] == 0)
    }

    @Test func ownershipFallsToTheOnlyProviderWithData() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 40, .codex: nil]
        )

        #expect(updated.provider == .claude)
        #expect(updated.lastUtilizations[.codex] == 10)
    }

    @Test func ownershipIsUnchangedWhenNoProviderHasData() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: nil, .codex: nil, .cursor: nil]
        )

        #expect(updated == current)
    }

    @Test func firstReadingKeepsDefaultOwnerAndStoresBaselines() {
        let updated = MenuBarOwnershipResolver.resolve(
            current: .claudeDefault,
            utilizations: [.claude: 40, .codex: 10, .cursor: 4]
        )

        #expect(updated.provider == .claude)
        #expect(updated.lastUtilizations[.claude] == 40)
        #expect(updated.lastUtilizations[.codex] == 10)
        #expect(updated.lastUtilizations[.cursor] == 4)
    }
}
