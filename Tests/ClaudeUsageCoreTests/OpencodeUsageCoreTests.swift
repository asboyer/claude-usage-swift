import XCTest

@testable import ClaudeUsageCore

final class OpencodeUsageCoreTests: XCTestCase {
    private var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    // MARK: - monthStart

    func testMonthStartSnapsToTheFirstAtMidnight() {
        let start = OpencodeUsageCore.monthStart(
            containing: date("2026-09-17T13:45:09Z"), calendar: utcCalendar)
        XCTAssertEqual(start, date("2026-09-01T00:00:00Z"))
    }

    func testMonthStartOnTheFirstReturnsThatSameDay() {
        let start = OpencodeUsageCore.monthStart(
            containing: date("2026-09-01T00:00:01Z"), calendar: utcCalendar)
        XCTAssertEqual(start, date("2026-09-01T00:00:00Z"))
    }

    func testMonthStartCrossesAYearBoundary() {
        let start = OpencodeUsageCore.monthStart(
            containing: date("2026-01-09T08:00:00Z"), calendar: utcCalendar)
        XCTAssertEqual(start, date("2026-01-01T00:00:00Z"))
    }

    // MARK: - rank

    func testRankOrdersByCostDescending() {
        let ranked = OpencodeUsageCore.rank([
            "claude-opus-4-8": 15.74,
            "kimi-k3": 62.70,
            "glm-5p2": 0.01,
        ])
        XCTAssertEqual(ranked.map { $0.modelID }, ["kimi-k3", "claude-opus-4-8", "glm-5p2"])
    }

    func testRankDropsModelsThatCostNothing() {
        let ranked = OpencodeUsageCore.rank([
            "gpt-5.6-sol": 0,
            "kimi-k3": 62.70,
        ])
        XCTAssertEqual(ranked.map { $0.modelID }, ["kimi-k3"])
    }

    func testRankBreaksTiesByModelIDSoOrderIsStable() {
        let ranked = OpencodeUsageCore.rank(["zeta": 1.0, "alpha": 1.0])
        XCTAssertEqual(ranked.map { $0.modelID }, ["alpha", "zeta"])
    }

    func testRankOfNoPaidModelsIsEmpty() {
        XCTAssertTrue(OpencodeUsageCore.rank(["gpt-5.6-sol": 0]).isEmpty)
    }

    // MARK: - displayName

    func testDisplayNameKeepsOnlyTheTrailingSegmentOfARoutedModel() {
        let spend = OpencodeModelSpend(
            modelID: "accounts/fireworks/models/kimi-k3", costUSD: 62.70)
        XCTAssertEqual(spend.displayName, "kimi-k3")
    }

    func testDisplayNameLeavesAPlainModelIDAlone() {
        let spend = OpencodeModelSpend(modelID: "claude-opus-4-8", costUSD: 15.74)
        XCTAssertEqual(spend.displayName, "claude-opus-4-8")
    }

    // MARK: - totalUSD

    func testTotalSumsEveryModelNotJustTheCollapsedOnes() {
        let usage = OpencodeUsage(
            models: OpencodeUsageCore.rank([
                "kimi-k3": 62.70,
                "kimi-k3-fast": 30.03,
                "claude-opus-4-8": 15.74,
                "fable-5": 0.02,
            ]),
            monthStart: date("2026-09-01T00:00:00Z")
        )
        XCTAssertEqual(usage.models.count, 4)
        XCTAssertEqual(usage.totalUSD, 108.49, accuracy: 0.001)
    }

    // MARK: - formatCost

    func testFormatCostAlwaysShowsTwoDecimals() {
        XCTAssertEqual(OpencodeUsageCore.formatCost(108.4), "$108.40")
        XCTAssertEqual(OpencodeUsageCore.formatCost(0), "$0.00")
        XCTAssertEqual(OpencodeUsageCore.formatCost(62.699), "$62.70")
    }
}
