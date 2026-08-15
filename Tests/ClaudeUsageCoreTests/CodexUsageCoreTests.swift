import XCTest

@testable import ClaudeUsageCore

final class CodexUsageCoreTests: XCTestCase {
    private func window(usedPercent: Double, windowSeconds: TimeInterval) -> CodexRateWindow {
        return CodexRateWindow(usedPercent: usedPercent, windowSeconds: windowSeconds, resetsAt: nil)
    }

    // MARK: - Weekly Window Selection

    func testSelectWeeklyPicksPrimaryWhenItIsTheSevenDayWindow() {
        let primary = window(usedPercent: 12, windowSeconds: 604_800)
        let selected = CodexWindowSelector.selectWeekly(primary: primary, secondary: nil)
        XCTAssertEqual(selected, primary)
    }

    func testSelectWeeklyPicksSecondaryWhenPrimaryIsTheSessionWindow() {
        let primary = window(usedPercent: 40, windowSeconds: 5 * 3600)
        let secondary = window(usedPercent: 12, windowSeconds: 604_800)
        let selected = CodexWindowSelector.selectWeekly(primary: primary, secondary: secondary)
        XCTAssertEqual(selected, secondary)
    }

    func testSelectWeeklyFallsBackToLongestWindowWhenNoneIsSevenDays() {
        let primary = window(usedPercent: 40, windowSeconds: 5 * 3600)
        let secondary = window(usedPercent: 12, windowSeconds: 30 * 86400)
        let selected = CodexWindowSelector.selectWeekly(primary: primary, secondary: secondary)
        XCTAssertEqual(selected, secondary)
    }

    func testSelectWeeklyReturnsNilWithoutWindows() {
        XCTAssertNil(CodexWindowSelector.selectWeekly(primary: nil, secondary: nil))
    }

    // MARK: - Menu Bar Ownership

    func testOwnershipMovesToCodexWhenCodexIncreases() {
        let current = MenuBarOwnership(provider: .claude, lastClaudeUtilization: 40, lastCodexUtilization: 10)
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            claudeUtilization: 40,
            codexUtilization: 14
        )

        XCTAssertEqual(updated.provider, .codex)
        XCTAssertEqual(updated.lastCodexUtilization, 14)
        XCTAssertEqual(updated.lastClaudeUtilization, 40)
    }

    func testOwnershipMovesToClaudeWhenClaudeIncreases() {
        let current = MenuBarOwnership(provider: .codex, lastClaudeUtilization: 40, lastCodexUtilization: 10)
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            claudeUtilization: 46,
            codexUtilization: 10
        )

        XCTAssertEqual(updated.provider, .claude)
    }

    func testOwnershipPrefersLargerIncreaseWhenBothMoved() {
        let current = MenuBarOwnership(provider: .claude, lastClaudeUtilization: 40, lastCodexUtilization: 10)
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            claudeUtilization: 41,
            codexUtilization: 18
        )

        XCTAssertEqual(updated.provider, .codex)
    }

    func testOwnershipIsUnchangedWhenNeitherIncreases() {
        let current = MenuBarOwnership(provider: .codex, lastClaudeUtilization: 40, lastCodexUtilization: 10)
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            claudeUtilization: 40,
            codexUtilization: 10
        )

        XCTAssertEqual(updated.provider, .codex)
    }

    func testLimitResetDoesNotTransferOwnership() {
        let current = MenuBarOwnership(provider: .codex, lastClaudeUtilization: 40, lastCodexUtilization: 90)
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            claudeUtilization: 5,
            codexUtilization: 0
        )

        XCTAssertEqual(updated.provider, .codex)
        XCTAssertEqual(updated.lastClaudeUtilization, 5)
        XCTAssertEqual(updated.lastCodexUtilization, 0)
    }

    func testOwnershipFallsToTheOnlyProviderWithData() {
        let current = MenuBarOwnership(provider: .codex, lastClaudeUtilization: 40, lastCodexUtilization: 10)
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            claudeUtilization: 40,
            codexUtilization: nil
        )

        XCTAssertEqual(updated.provider, .claude)
        XCTAssertEqual(updated.lastCodexUtilization, 10)
    }

    func testOwnershipIsUnchangedWhenNoProviderHasData() {
        let current = MenuBarOwnership(provider: .codex, lastClaudeUtilization: 40, lastCodexUtilization: 10)
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            claudeUtilization: nil,
            codexUtilization: nil
        )

        XCTAssertEqual(updated, current)
    }

    func testFirstReadingKeepsDefaultOwnerAndStoresBaselines() {
        let updated = MenuBarOwnershipResolver.resolve(
            current: .claudeDefault,
            claudeUtilization: 40,
            codexUtilization: 10
        )

        XCTAssertEqual(updated.provider, .claude)
        XCTAssertEqual(updated.lastClaudeUtilization, 40)
        XCTAssertEqual(updated.lastCodexUtilization, 10)
    }
}
