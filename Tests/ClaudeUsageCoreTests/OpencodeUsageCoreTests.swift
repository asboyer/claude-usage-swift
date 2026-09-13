import Foundation
import Testing

@testable import ClaudeUsageCore

struct OpencodeUsageCoreTests {
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

    @Test func monthStartSnapsToTheFirstAtMidnight() {
        let start = OpencodeUsageCore.monthStart(
            containing: date("2026-09-17T13:45:09Z"), calendar: utcCalendar)
        #expect(start == date("2026-09-01T00:00:00Z"))
    }

    @Test func monthStartOnTheFirstReturnsThatSameDay() {
        let start = OpencodeUsageCore.monthStart(
            containing: date("2026-09-01T00:00:01Z"), calendar: utcCalendar)
        #expect(start == date("2026-09-01T00:00:00Z"))
    }

    @Test func monthStartCrossesAYearBoundary() {
        let start = OpencodeUsageCore.monthStart(
            containing: date("2026-01-09T08:00:00Z"), calendar: utcCalendar)
        #expect(start == date("2026-01-01T00:00:00Z"))
    }

    // MARK: - rank

    @Test func rankOrdersByCostDescending() {
        let ranked = OpencodeUsageCore.rank([
            "claude-opus-4-8": 15.74,
            "kimi-k3": 62.70,
            "glm-5p2": 0.01,
        ])
        #expect(ranked.map { $0.modelID } == ["kimi-k3", "claude-opus-4-8", "glm-5p2"])
    }

    @Test func rankDropsModelsThatCostNothing() {
        let ranked = OpencodeUsageCore.rank([
            "gpt-5.6-sol": 0,
            "kimi-k3": 62.70,
        ])
        #expect(ranked.map { $0.modelID } == ["kimi-k3"])
    }

    @Test func rankBreaksTiesByModelIDSoOrderIsStable() {
        let ranked = OpencodeUsageCore.rank(["zeta": 1.0, "alpha": 1.0])
        #expect(ranked.map { $0.modelID } == ["alpha", "zeta"])
    }

    @Test func rankOfNoPaidModelsIsEmpty() {
        #expect(OpencodeUsageCore.rank(["gpt-5.6-sol": 0]).isEmpty)
    }

    // MARK: - displayName

    @Test func displayNameKeepsOnlyTheTrailingSegmentOfARoutedModel() {
        let spend = OpencodeModelSpend(
            modelID: "accounts/fireworks/models/kimi-k3", costUSD: 62.70)
        #expect(spend.displayName == "kimi-k3")
    }

    @Test func displayNameLeavesAPlainModelIDAlone() {
        let spend = OpencodeModelSpend(modelID: "claude-opus-4-8", costUSD: 15.74)
        #expect(spend.displayName == "claude-opus-4-8")
    }

    // MARK: - totalUSD

    @Test func totalSumsEveryModelNotJustTheCollapsedOnes() {
        let usage = OpencodeUsage(
            models: OpencodeUsageCore.rank([
                "kimi-k3": 62.70,
                "kimi-k3-fast": 30.03,
                "claude-opus-4-8": 15.74,
                "fable-5": 0.02,
            ]),
            monthStart: date("2026-09-01T00:00:00Z")
        )
        #expect(usage.models.count == 4)
        #expect(abs(usage.totalUSD - 108.49) <= 0.001)
    }

    // MARK: - formatCost

    @Test func formatCostAlwaysShowsTwoDecimals() {
        #expect(OpencodeUsageCore.formatCost(108.4) == "$108.40")
        #expect(OpencodeUsageCore.formatCost(0) == "$0.00")
        #expect(OpencodeUsageCore.formatCost(62.699) == "$62.70")
    }
}
