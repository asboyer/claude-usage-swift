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

    // MARK: - Five Hour Window Selection

    func testSelectFiveHourPicksTheSessionWindow() {
        let primary = window(usedPercent: 99, windowSeconds: 18000)
        let secondary = window(usedPercent: 62, windowSeconds: 604_800)
        let selected = CodexWindowSelector.selectFiveHour(primary: primary, secondary: secondary)
        XCTAssertEqual(selected, primary)
    }

    func testSelectFiveHourPicksSecondaryWhenPrimaryIsWeekly() {
        let primary = window(usedPercent: 62, windowSeconds: 604_800)
        let secondary = window(usedPercent: 99, windowSeconds: 18000)
        let selected = CodexWindowSelector.selectFiveHour(primary: primary, secondary: secondary)
        XCTAssertEqual(selected, secondary)
    }

    func testSelectFiveHourReturnsNilWhenNoSessionWindowIsReported() {
        let primary = window(usedPercent: 62, windowSeconds: 604_800)
        let secondary = window(usedPercent: 20, windowSeconds: 30 * 86400)
        XCTAssertNil(CodexWindowSelector.selectFiveHour(primary: primary, secondary: secondary))
    }

    // MARK: - Menu Bar Ownership

    func testOwnershipMovesToCodexWhenCodexIncreases() {
        let current = MenuBarOwnership(provider: .claude, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 40, .codex: 14]
        )

        XCTAssertEqual(updated.provider, .codex)
        XCTAssertEqual(updated.lastUtilizations[.codex], 14)
        XCTAssertEqual(updated.lastUtilizations[.claude], 40)
    }

    func testOwnershipMovesToClaudeWhenClaudeIncreases() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 46, .codex: 10]
        )

        XCTAssertEqual(updated.provider, .claude)
    }

    func testOwnershipMovesToCursorWhenCursorIncreases() {
        let current = MenuBarOwnership(
            provider: .claude,
            lastUtilizations: [.claude: 40, .codex: 10, .cursor: 2]
        )
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 40, .codex: 10, .cursor: 6]
        )

        XCTAssertEqual(updated.provider, .cursor)
        XCTAssertEqual(updated.lastUtilizations[.cursor], 6)
    }

    func testOwnershipPrefersLargerIncreaseWhenAllMoved() {
        let current = MenuBarOwnership(
            provider: .claude,
            lastUtilizations: [.claude: 40, .codex: 10, .cursor: 2]
        )
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 41, .codex: 18, .cursor: 3]
        )

        XCTAssertEqual(updated.provider, .codex)
    }

    func testOwnershipIsUnchangedWhenNeitherIncreases() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 40, .codex: 10]
        )

        XCTAssertEqual(updated.provider, .codex)
    }

    func testLimitResetDoesNotTransferOwnership() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 90])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 5, .codex: 0]
        )

        XCTAssertEqual(updated.provider, .codex)
        XCTAssertEqual(updated.lastUtilizations[.claude], 5)
        XCTAssertEqual(updated.lastUtilizations[.codex], 0)
    }

    func testOwnershipFallsToTheOnlyProviderWithData() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: 40, .codex: nil]
        )

        XCTAssertEqual(updated.provider, .claude)
        XCTAssertEqual(updated.lastUtilizations[.codex], 10)
    }

    func testOwnershipIsUnchangedWhenNoProviderHasData() {
        let current = MenuBarOwnership(provider: .codex, lastUtilizations: [.claude: 40, .codex: 10])
        let updated = MenuBarOwnershipResolver.resolve(
            current: current,
            utilizations: [.claude: nil, .codex: nil, .cursor: nil]
        )

        XCTAssertEqual(updated, current)
    }

    func testFirstReadingKeepsDefaultOwnerAndStoresBaselines() {
        let updated = MenuBarOwnershipResolver.resolve(
            current: .claudeDefault,
            utilizations: [.claude: 40, .codex: 10, .cursor: 4]
        )

        XCTAssertEqual(updated.provider, .claude)
        XCTAssertEqual(updated.lastUtilizations[.claude], 40)
        XCTAssertEqual(updated.lastUtilizations[.codex], 10)
        XCTAssertEqual(updated.lastUtilizations[.cursor], 4)
    }
}
