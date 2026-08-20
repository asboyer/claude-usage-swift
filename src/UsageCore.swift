import Foundation

// MARK: - Model Detection

enum UsageModelDetector {
    /// Detects the active weekly model preference from utilization values.
    /// Defaults to "opus" when no utilization data is available.
    static func detectPreferredModel(opusUtilization: Double?, sonnetUtilization: Double?) -> String {
        if let opusUtilization, opusUtilization > 0 {
            return "opus"
        }
        if let sonnetUtilization, sonnetUtilization > 0 {
            return "sonnet"
        }
        return "opus"
    }
}

// MARK: - Usage History

struct UsageSample: Codable, Equatable {
    let date: Date
    let utilization: Double
}

struct DailySummary: Codable, Equatable {
    let date: String
    var peakUtilization: Double
}

struct UsageHistoryFile: Codable, Equatable {
    var samples: [String: [UsageSample]]
    var dailySummaries: [String: [DailySummary]]
}

enum UsageHistoryRecorder {
    static let defaultMaxSamplesPerCategory = 100

    /// Returns an updated usage history file with a new utilization sample recorded.
    static func record(
        in historyFile: UsageHistoryFile,
        categoryKey: String,
        utilization: Double,
        now: Date = Date(),
        maxSamplesPerCategory: Int = defaultMaxSamplesPerCategory,
        dailyDateFormatter: DateFormatter
    ) -> UsageHistoryFile {
        var updatedHistoryFile = historyFile
        var categorySamples = updatedHistoryFile.samples[categoryKey] ?? []

        if let lastSample = categorySamples.last, utilization < lastSample.utilization - 5 {
            // Utilization dropped significantly, so a reset likely occurred.
            categorySamples.removeAll()
        }

        categorySamples.append(UsageSample(date: now, utilization: utilization))
        if categorySamples.count > maxSamplesPerCategory {
            categorySamples = Array(categorySamples.suffix(maxSamplesPerCategory))
        }
        updatedHistoryFile.samples[categoryKey] = categorySamples

        let currentDay = dailyDateFormatter.string(from: now)
        var summaries = updatedHistoryFile.dailySummaries[categoryKey] ?? []
        if let existingIndex = summaries.lastIndex(where: { $0.date == currentDay }) {
            summaries[existingIndex].peakUtilization = max(summaries[existingIndex].peakUtilization, utilization)
        } else {
            summaries.append(DailySummary(date: currentDay, peakUtilization: utilization))
        }
        updatedHistoryFile.dailySummaries[categoryKey] = summaries

        return updatedHistoryFile
    }
}

// MARK: - Usage Rate

struct UsageRate: Equatable {
    let perHour: Double?
    let perDay: Double?
    let descriptor: String
    let isWeekly: Bool
}

enum UsageRateCalculator {
    private static let minimumHoursWindow = 1.0 / 60.0
    private static let weeklyLookbackSeconds: TimeInterval = 24 * 3600
    private static let sessionLookbackSeconds: TimeInterval = 30 * 60

    static func calculateRate(
        from history: [UsageSample],
        currentUtilization: Double,
        isWeekly: Bool,
        now: Date = Date()
    ) -> UsageRate {
        guard let baseline = selectBaselineSample(from: history, isWeekly: isWeekly, now: now) else {
            return UsageRate(perHour: nil, perDay: nil, descriptor: "--", isWeekly: isWeekly)
        }

        let elapsedHours = max(now.timeIntervalSince(baseline.date) / 3600.0, minimumHoursWindow)
        let utilizationDelta = currentUtilization - baseline.utilization
        let effectiveDelta = utilizationDelta < 0 ? currentUtilization : utilizationDelta
        let hourlyRate = effectiveDelta / elapsedHours

        if isWeekly {
            let dailyRate = hourlyRate * 24
            return UsageRate(
                perHour: hourlyRate,
                perDay: dailyRate,
                descriptor: weeklyDescriptor(for: dailyRate),
                isWeekly: true
            )
        }

        return UsageRate(
            perHour: hourlyRate,
            perDay: hourlyRate * 24,
            descriptor: sessionDescriptor(for: hourlyRate),
            isWeekly: false
        )
    }

    private static func selectBaselineSample(
        from history: [UsageSample],
        isWeekly: Bool,
        now: Date
    ) -> UsageSample? {
        let lookbackSeconds = isWeekly ? weeklyLookbackSeconds : sessionLookbackSeconds
        for sample in history {
            if now.timeIntervalSince(sample.date) <= lookbackSeconds {
                return sample
            }
        }
        return history.first
    }

    private static func weeklyDescriptor(for dailyRate: Double) -> String {
        if dailyRate <= 10 { return "light" }
        if dailyRate <= 15 { return "steady" }
        if dailyRate <= 25 { return "fast" }
        return "heavy"
    }

    private static func sessionDescriptor(for hourlyRate: Double) -> String {
        if hourlyRate <= 12 { return "light" }
        if hourlyRate <= 20 { return "steady" }
        if hourlyRate <= 30 { return "fast" }
        if hourlyRate <= 50 { return "heavy" }
        return "extreme"
    }
}

// MARK: - Status Bar Display Mode

/// What the menu bar shows: the five-hour percentage, or the overage dollars.
enum StatusDisplayMode: String, Equatable {
    case percentage
    case overage
}

enum StatusDisplayModeSelector {
    /// Overage takes over the menu bar as soon as paid credits tick up — a scoped
    /// weekly limit can start billing while every percentage is still under 100 —
    /// and hands it back once the five-hour percentage moves again.
    static func select(
        previous: StatusDisplayMode,
        fiveHourUtilization: Double,
        previousFiveHourUtilization: Double?,
        spentCredits: Double?,
        previousSpentCredits: Double?
    ) -> StatusDisplayMode {
        guard let spentCredits else { return .percentage }
        if let previousSpentCredits, spentCredits > previousSpentCredits { return .overage }
        if let previousFiveHourUtilization, fiveHourUtilization > previousFiveHourUtilization {
            return .percentage
        }
        return previous
    }
}

// MARK: - Extra Usage Row Visibility

enum ExtraUsageRowVisibility {
    /// The Extra row is noise while the scoped weekly limit still has room, so by
    /// default it appears only once that limit is spent and starts billing credits.
    static func shouldShow(alwaysShow: Bool, scopedWeeklyUtilization: Double?) -> Bool {
        if alwaysShow { return true }
        guard let scopedWeeklyUtilization else { return false }
        return scopedWeeklyUtilization >= 100
    }
}
