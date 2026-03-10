import Cocoa
import Foundation

private let maxSamplesPerKey = 100
private let historyDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ClaudeUsage")
private let historyFileURL: URL = historyDirectory.appendingPathComponent("usage_history.json")
let dailyDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    return formatter
}()

private var historyCache: UsageHistoryFile?

func loadHistoryFile() -> UsageHistoryFile {
    if let historyCache {
        return historyCache
    }

    guard
        let data = try? Data(contentsOf: historyFileURL),
        let file = try? JSONDecoder().decode(UsageHistoryFile.self, from: data)
    else {
        return UsageHistoryFile(samples: [:], dailySummaries: [:])
    }

    historyCache = file
    return file
}

func saveHistoryFile(_ file: UsageHistoryFile) {
    historyCache = file
    try? FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(file) {
        try? data.write(to: historyFileURL, options: .atomic)
    }
}

func migrateUserDefaultsHistory() {
    let defaults = UserDefaults.standard
    guard defaults.bool(forKey: "historyMigrated") == false else {
        return
    }

    var file = loadHistoryFile()
    for key in allCategoryKeys {
        let defaultsKey = "usageHistory_\(key)"
        if
            let data = defaults.data(forKey: defaultsKey),
            let samples = try? JSONDecoder().decode([UsageSample].self, from: data)
        {
            file.samples[key] = samples
            defaults.removeObject(forKey: defaultsKey)
        }
    }
    saveHistoryFile(file)
    defaults.set(true, forKey: "historyMigrated")
}

func loadUsageHistory(_ categoryKey: String) -> [UsageSample] {
    return loadHistoryFile().samples[categoryKey] ?? []
}

func recordUsageSample(_ categoryKey: String, utilization: Double) {
    let updatedFile = UsageHistoryRecorder.record(
        in: loadHistoryFile(),
        categoryKey: categoryKey,
        utilization: utilization,
        maxSamplesPerCategory: maxSamplesPerKey,
        dailyDateFormatter: dailyDateFormatter
    )
    saveHistoryFile(updatedFile)
}

/// Computes usage rate from recent history.
func rateForCategory(_ categoryKey: String, currentUtil: Double, isWeekly: Bool) -> UsageRate {
    return UsageRateCalculator.calculateRate(
        from: loadUsageHistory(categoryKey),
        currentUtilization: currentUtil,
        isWeekly: isWeekly
    )
}

/// Maps rate descriptor text to a menu color.
func rateDescriptorColor(_ descriptor: String) -> NSColor {
    switch descriptor {
    case "light":
        return NSColor(calibratedHue: 120.0 / 360.0, saturation: 0.7, brightness: 0.9, alpha: 1.0)
    case "steady":
        return NSColor.secondaryLabelColor
    case "fast":
        return NSColor(calibratedHue: 55.0 / 360.0, saturation: 0.85, brightness: 1.0, alpha: 1.0)
    case "heavy":
        return NSColor(calibratedHue: 25.0 / 360.0, saturation: 0.85, brightness: 0.95, alpha: 1.0)
    case "extreme":
        return NSColor(calibratedHue: 0, saturation: 0.8, brightness: 1.0, alpha: 1.0)
    default:
        return NSColor.secondaryLabelColor
    }
}
