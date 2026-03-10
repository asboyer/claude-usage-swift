import XCTest
@testable import ClaudeUsageCore

final class UsageCoreTests: XCTestCase {
    private var dailyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    // MARK: - Model Detection

    func testDetectPreferredModelUsesOpusWhenAvailable() {
        let result = UsageModelDetector.detectPreferredModel(opusUtilization: 10, sonnetUtilization: 50)
        XCTAssertEqual(result, "opus")
    }

    func testDetectPreferredModelUsesSonnetWhenOpusEmpty() {
        let result = UsageModelDetector.detectPreferredModel(opusUtilization: 0, sonnetUtilization: 7)
        XCTAssertEqual(result, "sonnet")
    }

    func testDetectPreferredModelDefaultsToOpus() {
        let result = UsageModelDetector.detectPreferredModel(opusUtilization: nil, sonnetUtilization: nil)
        XCTAssertEqual(result, "opus")
    }

    // MARK: - History Recording

    func testRecordAddsSampleAndDailySummary() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let initial = UsageHistoryFile(samples: [:], dailySummaries: [:])

        let updated = UsageHistoryRecorder.record(
            in: initial,
            categoryKey: "five_hour",
            utilization: 12,
            now: start,
            dailyDateFormatter: dailyDateFormatter
        )

        XCTAssertEqual(updated.samples["five_hour"]?.count, 1)
        XCTAssertEqual(updated.samples["five_hour"]?.first?.utilization, 12)
        XCTAssertEqual(updated.dailySummaries["five_hour"]?.count, 1)
        XCTAssertEqual(updated.dailySummaries["five_hour"]?.first?.peakUtilization, 12)
    }

    func testRecordResetsHistoryAfterLargeDrop() {
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

        XCTAssertEqual(updated.samples["five_hour"]?.count, 1)
        XCTAssertEqual(updated.samples["five_hour"]?.first?.utilization, 40)
    }

    func testRecordTrimsToMaxSamples() {
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

        XCTAssertEqual(updated.samples["weekly"]?.count, 3)
        XCTAssertEqual(updated.samples["weekly"]?.first?.utilization, 1)
        XCTAssertEqual(updated.samples["weekly"]?.last?.utilization, 5)
    }

    func testRecordUpdatesExistingDailyPeak() {
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

        XCTAssertEqual(updated.dailySummaries["weekly"]?.first?.peakUtilization, 45)
    }

    // MARK: - Rate Calculation

    func testCalculateRateReturnsPlaceholderWithoutHistory() {
        let rate = UsageRateCalculator.calculateRate(
            from: [],
            currentUtilization: 20,
            isWeekly: false,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertNil(rate.perHour)
        XCTAssertEqual(rate.descriptor, "--")
    }

    func testCalculateRateUsesLookbackBaselineForSessionRate() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = UsageSample(date: now.addingTimeInterval(-4000), utilization: 10)
        let recent = UsageSample(date: now.addingTimeInterval(-600), utilization: 20)
        let rate = UsageRateCalculator.calculateRate(
            from: [old, recent],
            currentUtilization: 30,
            isWeekly: false,
            now: now
        )

        XCTAssertEqual(rate.perHour ?? 0, 60, accuracy: 0.1)
        XCTAssertEqual(rate.descriptor, "extreme")
    }

    func testCalculateRateFallsBackToEarliestSampleWhenNoLookbackMatch() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sample = UsageSample(date: now.addingTimeInterval(-7200), utilization: 10)
        let rate = UsageRateCalculator.calculateRate(
            from: [sample],
            currentUtilization: 34,
            isWeekly: false,
            now: now
        )

        XCTAssertEqual(rate.perHour ?? 0, 12, accuracy: 0.1)
        XCTAssertEqual(rate.descriptor, "light")
    }

    func testCalculateWeeklyRateUsesDailyDescriptors() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baseline = UsageSample(date: now.addingTimeInterval(-24 * 3600), utilization: 0)
        let rate = UsageRateCalculator.calculateRate(
            from: [baseline],
            currentUtilization: 16,
            isWeekly: true,
            now: now
        )

        XCTAssertEqual(rate.perDay ?? 0, 16, accuracy: 0.1)
        XCTAssertEqual(rate.descriptor, "fast")
    }

    func testCalculateRateHandlesResetWithNegativeDelta() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let baseline = UsageSample(date: now.addingTimeInterval(-3600), utilization: 80)
        let rate = UsageRateCalculator.calculateRate(
            from: [baseline],
            currentUtilization: 20,
            isWeekly: false,
            now: now
        )

        XCTAssertEqual(rate.perHour ?? 0, 20, accuracy: 0.1)
        XCTAssertEqual(rate.descriptor, "steady")
    }
}
