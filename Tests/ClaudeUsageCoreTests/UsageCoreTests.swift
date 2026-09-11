import Foundation
import Testing
@testable import ClaudeUsageCore

struct UsageCoreTests {
    private var dailyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    // MARK: - Model Detection

    @Test func detectPreferredModelUsesOpusWhenAvailable() {
        let result = UsageModelDetector.detectPreferredModel(opusUtilization: 10, sonnetUtilization: 50)
        #expect(result == "opus")
    }

    @Test func detectPreferredModelUsesSonnetWhenOpusEmpty() {
        let result = UsageModelDetector.detectPreferredModel(opusUtilization: 0, sonnetUtilization: 7)
        #expect(result == "sonnet")
    }

    @Test func detectPreferredModelDefaultsToOpus() {
        let result = UsageModelDetector.detectPreferredModel(opusUtilization: nil, sonnetUtilization: nil)
        #expect(result == "opus")
    }

    // MARK: - History Recording

    @Test func recordAddsSampleAndDailySummary() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let initial = UsageHistoryFile(samples: [:], dailySummaries: [:])

        let updated = UsageHistoryRecorder.record(
            in: initial,
            categoryKey: "five_hour",
            utilization: 12,
            now: start,
            dailyDateFormatter: dailyDateFormatter
        )

        #expect(updated.samples["five_hour"]?.count == 1)
        #expect(updated.samples["five_hour"]?.first?.utilization == 12)
        #expect(updated.dailySummaries["five_hour"]?.count == 1)
        #expect(updated.dailySummaries["five_hour"]?.first?.peakUtilization == 12)
    }

    @Test func recordResetsHistoryAfterLargeDrop() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sampleA = UsageSample(date: now.addingTimeInterval(-120), utilization: 50)
        let sampleB = UsageSample(date: now.addingTimeInterval(-60), utilization: 55)
        let initial = UsageHistoryFile(
            samples: ["five_hour": [sampleA, sampleB]],
            dailySummaries: [:]
        )

        let updated = UsageHistoryRecorder.record(
            in: initial,
            categoryKey: "five_hour",
            utilization: 40,
            now: now,
            dailyDateFormatter: dailyDateFormatter
        )

        #expect(updated.samples["five_hour"]?.count == 1)
        #expect(updated.samples["five_hour"]?.first?.utilization == 40)
    }

    @Test func recordTrimsToMaxSamples() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0..<3).map { index in
            UsageSample(date: now.addingTimeInterval(TimeInterval(index) * -60), utilization: Double(index))
        }
        let initial = UsageHistoryFile(samples: ["weekly": samples], dailySummaries: [:])

        let updated = UsageHistoryRecorder.record(
            in: initial,
            categoryKey: "weekly",
            utilization: 5,
            now: now,
            maxSamplesPerCategory: 3,
            dailyDateFormatter: dailyDateFormatter
        )

        #expect(updated.samples["weekly"]?.count == 3)
        #expect(updated.samples["weekly"]?.first?.utilization == 1)
        #expect(updated.samples["weekly"]?.last?.utilization == 5)
    }

    @Test func recordUpdatesExistingDailyPeak() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day = dailyDateFormatter.string(from: now)
        let initial = UsageHistoryFile(
            samples: [:],
            dailySummaries: ["weekly": [DailySummary(date: day, peakUtilization: 30)]]
        )

        let updated = UsageHistoryRecorder.record(
            in: initial,
            categoryKey: "weekly",
            utilization: 45,
            now: now,
            dailyDateFormatter: dailyDateFormatter
        )

        #expect(updated.dailySummaries["weekly"]?.first?.peakUtilization == 45)
    }

    // MARK: - Rate Calculation

    @Test func calculateRateReturnsPlaceholderWithoutHistory() {
        let rate = UsageRateCalculator.calculateRate(
            from: [],
            currentUtilization: 20,
            isWeekly: false,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(rate.perHour == nil)
        #expect(rate.descriptor == "--")
    }

    @Test func calculateRateUsesLookbackBaselineForSessionRate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = UsageSample(date: now.addingTimeInterval(-4000), utilization: 10)
        let recent = UsageSample(date: now.addingTimeInterval(-600), utilization: 20)
        let rate = UsageRateCalculator.calculateRate(
            from: [old, recent],
            currentUtilization: 30,
            isWeekly: false,
            now: now
        )

        #expect(abs((rate.perHour ?? 0) - 60) <= 0.1)
        #expect(rate.descriptor == "extreme")
    }

    @Test func calculateRateFallsBackToEarliestSampleWhenNoLookbackMatch() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = UsageSample(date: now.addingTimeInterval(-7200), utilization: 10)
        let rate = UsageRateCalculator.calculateRate(
            from: [sample],
            currentUtilization: 34,
            isWeekly: false,
            now: now
        )

        #expect(abs((rate.perHour ?? 0) - 12) <= 0.1)
        #expect(rate.descriptor == "light")
    }

    @Test func calculateWeeklyRateUsesDailyDescriptors() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baseline = UsageSample(date: now.addingTimeInterval(-24 * 3600), utilization: 0)
        let rate = UsageRateCalculator.calculateRate(
            from: [baseline],
            currentUtilization: 16,
            isWeekly: true,
            now: now
        )

        #expect(abs((rate.perDay ?? 0) - 16) <= 0.1)
        #expect(rate.descriptor == "fast")
    }

    @Test func calculateRateHandlesResetWithNegativeDelta() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baseline = UsageSample(date: now.addingTimeInterval(-3600), utilization: 80)
        let rate = UsageRateCalculator.calculateRate(
            from: [baseline],
            currentUtilization: 20,
            isWeekly: false,
            now: now
        )

        #expect(abs((rate.perHour ?? 0) - 20) <= 0.1)
        #expect(rate.descriptor == "steady")
    }

    // MARK: - Status Bar Display Mode

    private func selectMode(
        previous: StatusDisplayMode = .percentage,
        util: Double,
        priorUtil: Double?,
        spent: Double?,
        priorSpent: Double?
    ) -> StatusDisplayMode {
        return StatusDisplayModeSelector.select(
            previous: previous,
            fiveHourUtilization: util,
            previousFiveHourUtilization: priorUtil,
            spentCredits: spent,
            previousSpentCredits: priorSpent
        )
    }

    @Test func risingOverageTakesOverBelowFullUtilization() {
        let mode = selectMode(util: 70, priorUtil: 70, spent: 250, priorSpent: 100)
        #expect(mode == .overage)
    }

    @Test func risingOverageWinsWhenUtilizationAlsoRises() {
        let mode = selectMode(util: 72, priorUtil: 70, spent: 250, priorSpent: 100)
        #expect(mode == .overage)
    }

    @Test func risingUtilizationReclaimsMenuBarFromOverage() {
        let mode = selectMode(previous: .overage, util: 42, priorUtil: 40, spent: 250, priorSpent: 250)
        #expect(mode == .percentage)
    }

    @Test func flatUsageKeepsCurrentMode() {
        #expect(selectMode(previous: .overage, util: 40, priorUtil: 40, spent: 250, priorSpent: 250) == .overage)
        #expect(selectMode(previous: .percentage, util: 40, priorUtil: 40, spent: 250, priorSpent: 250) == .percentage)
    }

    @Test func missingSpendFallsBackToPercentage() {
        let mode = selectMode(previous: .overage, util: 40, priorUtil: 40, spent: nil, priorSpent: 250)
        #expect(mode == .percentage)
    }

    @Test func firstFetchShowsPercentage() {
        let mode = selectMode(util: 40, priorUtil: nil, spent: 250, priorSpent: nil)
        #expect(mode == .percentage)
    }

    // MARK: - Extra Usage Row Visibility

    private func shouldShowRow(
        alwaysShow: Bool = false,
        scopedWeekly: Double?,
        overallWeekly: Double?
    ) -> Bool {
        return ExtraUsageRowVisibility.shouldShow(
            alwaysShow: alwaysShow,
            scopedWeeklyUtilization: scopedWeekly,
            overallWeeklyUtilization: overallWeekly
        )
    }

    @Test func extraRowHiddenWhileBothWeeklyLimitsHaveRoom() {
        #expect(!shouldShowRow(scopedWeekly: 70, overallWeekly: 45))
    }

    @Test func extraRowShownWhenScopedWeeklyIsExhausted() {
        #expect(shouldShowRow(scopedWeekly: 100, overallWeekly: 45))
    }

    @Test func extraRowShownWhenOverallWeeklyIsExhausted() {
        #expect(shouldShowRow(scopedWeekly: 70, overallWeekly: 100))
    }

    @Test func extraRowStaysHiddenJustUnderEitherLimit() {
        #expect(!shouldShowRow(scopedWeekly: 99.9, overallWeekly: 99.9))
    }

    @Test func extraRowHiddenWithoutUtilizationData() {
        #expect(!shouldShowRow(scopedWeekly: nil, overallWeekly: nil))
    }

    @Test func extraRowShownOnOverallWeeklyWithoutScopedData() {
        #expect(shouldShowRow(scopedWeekly: nil, overallWeekly: 100))
    }

    @Test func alwaysShowOverridesEverything() {
        #expect(shouldShowRow(alwaysShow: true, scopedWeekly: 0, overallWeekly: 0))
        #expect(shouldShowRow(alwaysShow: true, scopedWeekly: nil, overallWeekly: nil))
    }

    // MARK: - Extra Usage Credits

    @Test func formatCreditsUsesReportedDecimalPlaces() {
        #expect(ExtraUsageFormatter.formatCredits(73333, decimalPlaces: 2) == "$733.33")
        #expect(ExtraUsageFormatter.formatCredits(500, decimalPlaces: 0) == "$500")
    }

    @Test func formatCreditsDefaultsToTwoDecimalPlaces() {
        #expect(ExtraUsageFormatter.formatCredits(73333, decimalPlaces: nil) == "$733.33")
    }

    @Test func formatCreditsHandlesZero() {
        #expect(ExtraUsageFormatter.formatCredits(0, decimalPlaces: 2) == "$0.00")
    }
}
