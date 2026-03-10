import Cocoa
import Carbon.HIToolbox
import Security
import ServiceManagement
import SQLite3
import CommonCrypto
import WebKit

// MARK: - Constants

let appVersion = "2.1.34"

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm:ss a"
    f.timeZone = TimeZone(identifier: "America/New_York")
    return f
}()

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

// MARK: - Usage API (OAuth + Claude Desktop cookies)

private let userAgents: [String] = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0",
    "curl/8.4.0"
]
private var userAgentIndex = 0

/// Last request/response from fetchUsage for Debug Mode copy (formatted JSON, indent 4),
/// plus the User-Agent used for building a curl command.
var lastRequestForDebug: String?
var lastResponseForDebug: String?
var lastUserAgentForDebug: String?

struct UsageResponse: Codable {
    let five_hour: UsageLimit?
    let seven_day: UsageLimit?
    let seven_day_opus: UsageLimit?
    let seven_day_sonnet: UsageLimit?
    let seven_day_oauth_apps: UsageLimit?
    let seven_day_cowork: UsageLimit?
    let extra_usage: ExtraUsage?
}

func detectModel(_ usage: UsageResponse) -> String {
    return UsageModelDetector.detectPreferredModel(
        opusUtilization: usage.seven_day_opus?.utilization,
        sonnetUtilization: usage.seven_day_sonnet?.utilization
    )
}

struct UsageLimit: Codable {
    let utilization: Double
    let resets_at: String?
}

struct ExtraUsage: Codable {
    let is_enabled: Bool
    let monthly_limit: Double?
    let used_credits: Double?
    let utilization: Double?
}

struct APIErrorResponse: Codable {
    let error: APIError?
    struct APIError: Codable {
        let message: String?
        let type: String?
    }
}

// MARK: - Usage History (persistent file-based storage)

private let maxSamplesPerKey = 100

private let historyDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ClaudeUsage")

private let historyFileURL: URL = historyDirectory.appendingPathComponent("usage_history.json")

private let dailyDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = .current
    return f
}()

private var historyCache: UsageHistoryFile?

func loadHistoryFile() -> UsageHistoryFile {
    if let cached = historyCache { return cached }
    guard let data = try? Data(contentsOf: historyFileURL),
          let file = try? JSONDecoder().decode(UsageHistoryFile.self, from: data) else {
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
    let ud = UserDefaults.standard
    guard ud.bool(forKey: "historyMigrated") == false else { return }
    var file = loadHistoryFile()
    for key in allCategoryKeys {
        let udKey = "usageHistory_\(key)"
        if let data = ud.data(forKey: udKey),
           let samples = try? JSONDecoder().decode([UsageSample].self, from: data) {
            file.samples[key] = samples
            ud.removeObject(forKey: udKey)
        }
    }
    saveHistoryFile(file)
    ud.set(true, forKey: "historyMigrated")
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

/// Compute usage rate from recent history.
/// For 5-hour categories uses a ~30-min lookback and reports %/hr.
/// For 7-day categories uses a ~24-hour lookback and reports %/day.
func rateForCategory(_ categoryKey: String, currentUtil: Double, isWeekly: Bool) -> UsageRate {
    return UsageRateCalculator.calculateRate(
        from: loadUsageHistory(categoryKey),
        currentUtilization: currentUtil,
        isWeekly: isWeekly
    )
}

/// Map rate descriptor to a color for the rate menu item
func rateDescriptorColor(_ descriptor: String) -> NSColor {
    switch descriptor {
    case "light":   return NSColor(calibratedHue: 120.0/360.0, saturation: 0.7, brightness: 0.9, alpha: 1.0)
    case "steady":  return NSColor.secondaryLabelColor
    case "fast":    return NSColor(calibratedHue: 55.0/360.0, saturation: 0.85, brightness: 1.0, alpha: 1.0)
    case "heavy":   return NSColor(calibratedHue: 25.0/360.0, saturation: 0.85, brightness: 0.95, alpha: 1.0)
    case "extreme": return NSColor(calibratedHue: 0, saturation: 0.8, brightness: 1.0, alpha: 1.0)
    default:        return NSColor.secondaryLabelColor
    }
}

// MARK: - Usage Heatmap

func generateHeatmapHTML() -> String {
    let file = loadHistoryFile()
    let summaries = file.dailySummaries["five_hour"] ?? []

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    // Build lookup from date string -> peak utilization
    var lookup: [String: Double] = [:]
    for s in summaries { lookup[s.date] = s.peakUtilization }

    // Generate 90 days of data ending today
    var days: [(dateStr: String, weekday: Int, weekIndex: Int, level: Int)] = []
    guard let startDate = calendar.date(byAdding: .day, value: -89, to: today) else { return "" }

    // Align start to a Sunday so columns are full weeks
    let startWeekday = calendar.component(.weekday, from: startDate)
    let alignedStart = calendar.date(byAdding: .day, value: -(startWeekday - 1), to: startDate)!
    let totalDays = calendar.dateComponents([.day], from: alignedStart, to: today).day! + 1
    let numWeeks = (totalDays + 6) / 7

    for i in 0..<(numWeeks * 7) {
        guard let d = calendar.date(byAdding: .day, value: i, to: alignedStart) else { continue }
        let ds = dailyDateFormatter.string(from: d)
        let wd = calendar.component(.weekday, from: d) - 1 // 0=Sun
        let wi = i / 7
        let peak = lookup[ds]
        let level: Int
        if d > today {
            level = -1 // future
        } else if let p = peak {
            if p >= 90 { level = 4 }
            else if p >= 61 { level = 3 }
            else if p >= 31 { level = 2 }
            else if p >= 1 { level = 1 }
            else { level = 0 }
        } else {
            level = 0
        }
        days.append((ds, wd, wi, level))
    }

    // Month labels
    var monthLabels: [(weekIndex: Int, label: String)] = []
    let monthFormatter = DateFormatter()
    monthFormatter.dateFormat = "MMM"
    var lastMonth = -1
    for i in 0..<(numWeeks * 7) {
        guard let d = calendar.date(byAdding: .day, value: i, to: alignedStart) else { continue }
        let m = calendar.component(.month, from: d)
        if m != lastMonth && calendar.component(.weekday, from: d) == 1 {
            lastMonth = m
            monthLabels.append((i / 7, monthFormatter.string(from: d)))
        }
    }

    // Build cells HTML
    var cellsHTML = ""
    for day in days {
        if day.level == -1 { continue }
        let tooltip = day.level > 0
            ? "\(day.dateStr): \(Int(lookup[day.dateStr] ?? 0))% peak"
            : "\(day.dateStr): no usage"
        cellsHTML += """
        <rect width="11" height="11" x="\(day.weekIndex * 14)" y="\(day.weekday * 14)" \
        rx="2" ry="2" class="level-\(day.level)"><title>\(tooltip)</title></rect>\n
        """
    }

    // Month labels SVG
    var monthLabelsHTML = ""
    for ml in monthLabels {
        monthLabelsHTML += """
        <text x="\(ml.weekIndex * 14 + 2)" y="-4" class="month-label">\(ml.label)</text>\n
        """
    }

    // Day labels
    let dayLabelsHTML = """
    <text x="-28" y="23" class="day-label">Mon</text>
    <text x="-28" y="51" class="day-label">Wed</text>
    <text x="-28" y="79" class="day-label">Fri</text>
    """

    let svgWidth = numWeeks * 14 + 2
    let svgHeight = 7 * 14 + 2

    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      @media (prefers-color-scheme: dark) {
        body { background: #1e1e1e; color: #ccc; }
        .level-0 { fill: #2d2d2d; }
        .level-1 { fill: #0e4429; }
        .level-2 { fill: #006d32; }
        .level-3 { fill: #26a641; }
        .level-4 { fill: #39d353; }
        .legend-text { fill: #8b949e; }
      }
      @media (prefers-color-scheme: light) {
        body { background: #fff; color: #333; }
        .level-0 { fill: #ebedf0; }
        .level-1 { fill: #9be9a8; }
        .level-2 { fill: #40c463; }
        .level-3 { fill: #30a14e; }
        .level-4 { fill: #216e39; }
        .legend-text { fill: #656d76; }
      }
      body {
        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
        display: flex; flex-direction: column; align-items: center;
        justify-content: center; height: 100vh; margin: 0; padding: 16px;
        box-sizing: border-box;
      }
      h3 { font-size: 13px; font-weight: 600; margin: 0 0 12px 0; }
      .month-label { font-size: 10px; fill: currentColor; }
      .day-label { font-size: 10px; fill: currentColor; }
      .legend { display: flex; align-items: center; gap: 4px; margin-top: 10px; font-size: 11px; }
      .legend svg rect { rx: 2; ry: 2; }
    </style>
    </head>
    <body>
      <h3>Claude Usage — Last 90 Days</h3>
      <svg width="\(svgWidth + 36)" height="\(svgHeight + 20)">
        <g transform="translate(34, 16)">
          \(monthLabelsHTML)
          \(dayLabelsHTML)
          \(cellsHTML)
        </g>
      </svg>
      <div class="legend">
        <span class="legend-text">Less</span>
        <svg width="11" height="11"><rect width="11" height="11" class="level-0"/></svg>
        <svg width="11" height="11"><rect width="11" height="11" class="level-1"/></svg>
        <svg width="11" height="11"><rect width="11" height="11" class="level-2"/></svg>
        <svg width="11" height="11"><rect width="11" height="11" class="level-3"/></svg>
        <svg width="11" height="11"><rect width="11" height="11" class="level-4"/></svg>
        <span class="legend-text">More</span>
      </div>
    </body>
    </html>
    """
}

// MARK: - Claude Desktop cookie-based usage (claude-web-usage strategy)

private func getClaudeDesktopEncryptionKey() -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Safe Storage",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let passwordData = result as? Data,
          !passwordData.isEmpty else {
        return nil
    }

    // Chromium-style PBKDF2(password, "saltysalt", 1003, 16, SHA1)
    let saltData = "saltysalt".data(using: .utf8)!
    var derivedKey = Data(repeating: 0, count: 16)
    let keyLength = derivedKey.count

    let resultCode = derivedKey.withUnsafeMutableBytes { derivedBytes -> Int32 in
        saltData.withUnsafeBytes { saltBytes -> Int32 in
            passwordData.withUnsafeBytes { passwordBytes -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: UInt8.self).baseAddress!,
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress!,
                    saltData.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003,
                    derivedBytes.bindMemory(to: UInt8.self).baseAddress!,
                    keyLength
                )
            }
        }
    }

    guard resultCode == kCCSuccess else { return nil }
    return derivedKey
}

private func decryptClaudeCookie(_ encrypted: Data, key: Data) -> String? {
    // Expect Chromium "v10" prefix
    guard encrypted.count > 3,
          String(data: encrypted.prefix(3), encoding: .utf8) == "v10" else {
        return nil
    }
    let data = encrypted.dropFirst(3)

    var outData = Data(count: data.count + kCCBlockSizeAES128)
    let outCapacity = outData.count
    var outLength: size_t = 0

    let iv = Data(repeating: 0x20, count: 16)

    let status = key.withUnsafeBytes { keyBytes in
        data.withUnsafeBytes { dataBytes in
            iv.withUnsafeBytes { ivBytes in
                outData.withUnsafeMutableBytes { outBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.bindMemory(to: UInt8.self).baseAddress!,
                        key.count,
                        ivBytes.bindMemory(to: UInt8.self).baseAddress!,
                        dataBytes.bindMemory(to: UInt8.self).baseAddress!,
                        data.count,
                        outBytes.bindMemory(to: UInt8.self).baseAddress!,
                        outCapacity,
                        &outLength
                    )
                }
            }
        }
    }

    guard status == kCCSuccess else { return nil }
    outData.removeSubrange(outLength..<outData.count)

    // Strip 32-byte prefix; remaining UTF-8 string is the cookie value.
    guard outData.count > 32 else { return nil }
    let valueData = outData.dropFirst(32)
    return String(data: valueData, encoding: .utf8)
}

private func getClaudeCookie(name: String, key: Data) -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dbURL = home
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
        .appendingPathComponent("Claude")
        .appendingPathComponent("Cookies")

    var db: OpaquePointer?
    guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else { return nil }
    defer { sqlite3_close(db) }

    let query = "SELECT encrypted_value FROM cookies WHERE host_key = '.claude.ai' AND name = '\(name)' LIMIT 1;"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(stmt) }

    if sqlite3_step(stmt) == SQLITE_ROW {
        if let blobPtr = sqlite3_column_blob(stmt, 0) {
            let size = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: blobPtr, count: size)
            return decryptClaudeCookie(data, key: key)
        }
    }
    return nil
}

func fetchUsageViaClaudeDesktopCookies(completion: @escaping (UsageResponse?) -> Void) {
    guard let key = getClaudeDesktopEncryptionKey() else {
        completion(nil)
        return
    }
    guard let sessionKey = getClaudeCookie(name: "sessionKey", key: key),
          let orgId = getClaudeCookie(name: "lastActiveOrg", key: key) else {
        completion(nil)
        return
    }

    guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
        completion(nil)
        return
    }

    var request = URLRequest(url: url)
    request.setValue("sessionKey=\(sessionKey); lastActiveOrg=\(orgId)", forHTTPHeaderField: "Cookie")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

    // Debug Mode: record a sanitized request description
    let requestDict: [String: Any] = [
        "url": url.absoluteString,
        "method": "GET",
        "headers": [
            "Cookie": "sessionKey=***; lastActiveOrg=\(orgId)",
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        ]
    ]
    if let reqData = try? JSONSerialization.data(withJSONObject: requestDict, options: [.prettyPrinted]) {
        lastRequestForDebug = String(data: reqData, encoding: .utf8)
    }

    let session = URLSession(configuration: .ephemeral)
    session.dataTask(with: request) { data, response, _ in
        guard let data = data else {
            completion(nil)
            return
        }
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let s = String(data: pretty, encoding: .utf8) {
            lastResponseForDebug = s
        } else {
            lastResponseForDebug = String(data: data, encoding: .utf8)
        }

        guard let http = response as? HTTPURLResponse else {
            completion(nil)
            return
        }
        // Treat 2xx as success; anything else as failure (no special rate-limit UI here).
        guard (200..<300).contains(http.statusCode),
              let usage = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            completion(nil)
            return
        }
        completion(usage)
    }.resume()
}

// All trackable usage categories
let allCategoryKeys: [String] = [
    "five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet",
    "seven_day_oauth_apps", "seven_day_cowork", "extra_usage"
]
let categoryLabels: [String: String] = [
    "five_hour": "5-hour",
    "seven_day": "Weekly",
    "seven_day_opus": "Opus",
    "seven_day_sonnet": "Sonnet",
    "seven_day_oauth_apps": "OAuth Apps",
    "seven_day_cowork": "Cowork",
    "extra_usage": "Extra"
]
let defaultPinnedKeys: Set<String> = ["five_hour", "seven_day", "seven_day_sonnet", "extra_usage"]

func getOAuthToken() -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let json = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let jsonData = json.data(using: .utf8),
          let creds = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
          let oauth = creds["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String else {
        return nil
    }
    return token
}

func fetchUsage(token: String, completion: @escaping (UsageResponse?, _ rateLimited: Bool) -> Void) {
    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
        completion(nil, false)
        return
    }

    userAgentIndex = (userAgentIndex + 1) % userAgents.count
    let userAgent = userAgents[userAgentIndex]
    lastUserAgentForDebug = userAgent

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

    let requestDict: [String: Any] = [
        "url": url.absoluteString,
        "method": "GET",
        "headers": [
            "Authorization": "Bearer ***",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": userAgent
        ]
    ]
    if let reqData = try? JSONSerialization.data(withJSONObject: requestDict, options: [.prettyPrinted]) {
        lastRequestForDebug = String(data: reqData, encoding: .utf8)
    }

    let session = URLSession(configuration: .ephemeral)
    session.dataTask(with: request) { data, _, _ in
        guard let data = data else {
            completion(nil, false)
            return
        }
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let s = String(data: pretty, encoding: .utf8) {
            lastResponseForDebug = s
        } else {
            lastResponseForDebug = String(data: data, encoding: .utf8)
        }
        if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
           errorResponse.error?.type == "rate_limit_error" {
            completion(nil, true)
            return
        }
        guard let usage = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            completion(nil, false)
            return
        }
        completion(usage, false)
    }.resume()
}

func formatReset(_ isoString: String) -> String {
    if let date = isoFormatter.date(from: isoString) {
        return formatResetDate(date)
    }
    if let date = isoFormatterNoFrac.date(from: isoString) {
        return formatResetDate(date)
    }
    return "?"
}

func formatResetDate(_ date: Date) -> String {
    let diff = date.timeIntervalSince(Date())
    if diff < 0 { return "now" }

    let hours = Int(diff) / 3600
    let mins = (Int(diff) % 3600) / 60

    if hours == 0 {
        return "\(mins)m"
    } else if hours < 24 {
        return "\(hours)h \(mins)m"
    } else {
        return dateFormatter.string(from: date)
    }
}

// MARK: - Sound Playback

func playClicks(count: Int, soundName: String, delay: TimeInterval = 0.15, completion: (() -> Void)? = nil) {
    guard count > 0 else {
        completion?()
        return
    }
    if let sound = NSSound(named: NSSound.Name(soundName)) {
        sound.play()
    }
    if count > 1 {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            playClicks(count: count - 1, soundName: soundName, delay: delay, completion: completion)
        }
    } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completion?()
        }
    }
}

func playAlarmBursts(bursts: Int = 3, clicksPerBurst: Int = 5, soundName: String, checkMuted: @escaping () -> Bool, completion: (() -> Void)? = nil) {
    guard bursts > 0 else {
        completion?()
        return
    }
    if checkMuted() {
        completion?()
        return
    }
    playClicks(count: clicksPerBurst, soundName: soundName) {
        if bursts > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playAlarmBursts(bursts: bursts - 1, clicksPerBurst: clicksPerBurst, soundName: soundName, checkMuted: checkMuted, completion: completion)
            }
        } else {
            completion?()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?

    // Store state
    var currentPct: String = "..."
    var hasData = false

    // Data-driven usage items: key -> menu item
    var usageItems: [String: NSMenuItem] = [:]
    var rateItems: [String: NSMenuItem] = [:]
    var updatedItem: NSMenuItem!
    var rateLimitItem: NSMenuItem!
    var isRateLimited = false

    // Usage graph
    var graphPanel: NSPanel?

    // Which keys are pinned to the main menu
    var menuReady = false
    var suppressRebuild = false
    var needsMenuRebuild = false
    var pinnedKeys: Set<String> = defaultPinnedKeys {
        didSet {
            UserDefaults.standard.set(Array(pinnedKeys), forKey: "pinnedKeys")
            if menuReady && !suppressRebuild { rebuildMenu() }
        }
    }

    // More submenu items for toggling
    var moreToggleItems: [String: NSMenuItem] = [:]
    var moreMenu: NSMenu!

    // Refresh interval items
    var interval1mItem: NSMenuItem!
    var interval5mItem: NSMenuItem!
    var interval30mItem: NSMenuItem!
    var interval1hItem: NSMenuItem!

    // Notification menu items
    var alert100Item: NSMenuItem!
    var alertLimitItem: NSMenuItem!
    var alarmAfter100Item: NSMenuItem!
    var alarmAfterUsedItem: NSMenuItem!
    var alarmAfterAnyItem: NSMenuItem!
    var alarmOffItem: NSMenuItem!
    var alarmSkipItem: NSMenuItem!

    // Sound menu items
    var soundItems: [NSMenuItem] = []

    // Colors toggle
    var colorsEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(colorsEnabled, forKey: "colorsEnabled")
            colorsItem?.state = colorsEnabled ? .on : .off
        }
    }
    var colorsItem: NSMenuItem!

    // Rate insight toggle
    var rateInsightEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(rateInsightEnabled, forKey: "rateInsightEnabled")
            rateInsightItem?.state = rateInsightEnabled ? .on : .off
            for (_, item) in rateItems { item.isHidden = !rateInsightEnabled }
        }
    }
    var rateInsightItem: NSMenuItem!

    // Open at login toggle
    var openAtLoginEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(openAtLoginEnabled, forKey: "openAtLoginEnabled")
            openAtLoginItem?.state = openAtLoginEnabled ? .on : .off
            updateLoginItem()
        }
    }
    var openAtLoginItem: NSMenuItem!

    // Usage source: 0 = Desktop cookies (default), 1 = OAuth API
    var usageSource: Int = 0 {
        didSet {
            UserDefaults.standard.set(usageSource, forKey: "usageSource")
            updateUsageSourceMenu()
        }
    }
    var usageSourceCookiesItem: NSMenuItem!
    var usageSourceOAuthItem: NSMenuItem!

    // Current interval in seconds
    var refreshInterval: TimeInterval = 300 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            updateIntervalMenu()
            restartTimer()
        }
    }

    // Notification preferences
    var alert100Enabled: Bool = true {
        didSet { UserDefaults.standard.set(alert100Enabled, forKey: "alert100Enabled") }
    }
    var alertLimitEnabled: Bool = true {
        didSet { UserDefaults.standard.set(alertLimitEnabled, forKey: "alertLimitEnabled") }
    }
    // 0=Off, 1=After 100%, 2=After any used, 3=After any session
    var alarmCondition: Int = 0 {
        didSet {
            UserDefaults.standard.set(alarmCondition, forKey: "alarmCondition")
            updateAlarmMenu()
        }
    }
    var alarmSkipIfPrevZero: Bool = false {
        didSet { UserDefaults.standard.set(alarmSkipIfPrevZero, forKey: "alarmSkipIfPrevZero") }
    }
    var selectedSoundName: String = "Tink" {
        didSet {
            UserDefaults.standard.set(selectedSoundName, forKey: "selectedSoundName")
            updateSoundMenu()
        }
    }

    // Local key monitor for menu shortcuts (x, c, r) when menu is open
    var menuKeyMonitor: Any?

    // Global hotkey
    var hotKeyRef: EventHotKeyRef?
    var eventHandlerRef: EventHandlerRef?
    var lastMenuCloseTime: Date = .distantPast
    var hotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_X) // default: X (Cmd+Shift+X)
    var hotkeyModifiers: UInt32 = UInt32(cmdKey | shiftKey) // default: Cmd+Shift
    var hotkeyCurrentItem: NSMenuItem!
    var hotkeyRecordItem: NSMenuItem!
    var hotkeyRemoveItem: NSMenuItem!

    // Transition tracking
    var previousFiveHourUtil: Double = -1
    var previousExtraUtil: Double = -1
    var lastKnownResetDate: Date?
    var lastSessionFinalUtil: Double = 0
    var previousSessionHadUsage: Bool = false
    var alarmIsPlaying: Bool = false
    var alarmCheckTimer: Timer?
    var lastFetchDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Migrate usage history from UserDefaults to persistent file
        migrateUserDefaultsHistory()

        // Load saved preferences
        let ud = UserDefaults.standard
        let savedInterval = ud.double(forKey: "refreshInterval")
        if savedInterval > 0 { refreshInterval = savedInterval }

        if ud.object(forKey: "alert100Enabled") != nil {
            alert100Enabled = ud.object(forKey: "alert100Enabled") as? Bool ?? true
        }
        if ud.object(forKey: "alertLimitEnabled") != nil {
            alertLimitEnabled = ud.object(forKey: "alertLimitEnabled") as? Bool ?? true
        }
        alarmCondition = ud.object(forKey: "alarmCondition") as? Int ?? 0
        if ud.object(forKey: "alarmSkipIfPrevZero") != nil {
            alarmSkipIfPrevZero = ud.object(forKey: "alarmSkipIfPrevZero") as? Bool ?? false
        }
        selectedSoundName = ud.object(forKey: "selectedSoundName") as? String ?? "Tink"
        if ud.object(forKey: "colorsEnabled") != nil {
            colorsEnabled = ud.bool(forKey: "colorsEnabled")
        }
        if ud.object(forKey: "rateInsightEnabled") != nil {
            rateInsightEnabled = ud.bool(forKey: "rateInsightEnabled")
        }
        if ud.object(forKey: "openAtLoginEnabled") != nil {
            openAtLoginEnabled = ud.bool(forKey: "openAtLoginEnabled")
        }
        if ud.object(forKey: "usageSource") != nil {
            usageSource = ud.integer(forKey: "usageSource")
        } else {
            usageSource = 0 // default: Desktop cookies
        }

        if let saved = ud.object(forKey: "pinnedKeys") as? [String] {
            pinnedKeys = Set(saved)
        }

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "..."

        // Create usage menu items and rate sub-items for all categories
        for key in allCategoryKeys {
            let label = categoryLabels[key] ?? key
            let item = NSMenuItem(title: "\(label): ...", action: #selector(noop), keyEquivalent: "")
            item.target = self
            usageItems[key] = item

            let rateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            rateItem.isEnabled = false
            rateItem.isHidden = true
            rateItems[key] = rateItem
        }
        updatedItem = NSMenuItem(title: "Updated: --", action: nil, keyEquivalent: "")
        rateLimitItem = NSMenuItem(title: "Rate limited. Try again later.", action: nil, keyEquivalent: "")
        rateLimitItem.isEnabled = false

        // Build the full menu
        menu = NSMenu()
        menu.delegate = self
        buildMenu()
        menuReady = true

        // Set menu directly for proper display
        statusItem.menu = menu

        // Update checkmarks
        updateIntervalMenu()
        updateNotificationMenu()
        updateAlarmMenu()
        updateSoundMenu()
        updateUsageSourceMenu()

        // Initial fetch
        refresh()

        // Start timer
        restartTimer()

        // Load saved hotkey
        if ud.object(forKey: "hotkeyKeyCode") != nil {
            hotkeyKeyCode = UInt32(ud.integer(forKey: "hotkeyKeyCode"))
            hotkeyModifiers = UInt32(ud.integer(forKey: "hotkeyModifiers"))
        }

        // Register global hotkey
        installHotkeyHandler()
        if hotkeyKeyCode != UInt32.max {
            registerGlobalHotkey()
        }

        // Subscribe to sleep/wake notifications
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleSleep), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleWake), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    // MARK: - Global Hotkey

    func installHotkeyHandler() {
        var eventType = EventTypeSpec(eventClass: UInt32(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            let app = NSApplication.shared.delegate as! AppDelegate
            if Date().timeIntervalSince(app.lastMenuCloseTime) > 0.5 {
                app.showMenu()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)
    }

    func registerGlobalHotkey() {
        unregisterGlobalHotkey()
        guard hotkeyKeyCode != UInt32.max else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5553), id: 1)
        RegisterEventHotKey(hotkeyKeyCode, hotkeyModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        updateHotkeyMenu()
    }

    func unregisterGlobalHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    func saveHotkeyPrefs() {
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(hotkeyModifiers), forKey: "hotkeyModifiers")
    }

    func updateHotkeyMenu() {
        if hotkeyKeyCode == UInt32.max {
            hotkeyCurrentItem?.title = "Current: None"
            hotkeyRemoveItem?.isEnabled = false
        } else {
            hotkeyCurrentItem?.title = "Current: \(hotkeyDisplayString())"
            hotkeyRemoveItem?.isEnabled = true
        }
    }

    func hotkeyDisplayString() -> String {
        guard hotkeyKeyCode != UInt32.max else { return "None" }
        var parts: [String] = []
        if hotkeyModifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        if hotkeyModifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if hotkeyModifiers & UInt32(optionKey) != 0 { parts.append("Opt") }
        if hotkeyModifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        parts.append(keyCodeToString(hotkeyKeyCode))
        return parts.joined(separator: "+")
    }

    func keyCodeToString(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Esc",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Grave): "`",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    /// Convert NSEvent modifier flags to Carbon modifier mask
    func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    func menuWillOpen(_ menu: NSMenu) {
        installMenuKeyMonitor()
    }

    func menuDidClose(_ menu: NSMenu) {
        uninstallMenuKeyMonitor()
        lastMenuCloseTime = Date()
        if !hasData {
            statusItem.button?.title = "..."
        }
    }

    func installMenuKeyMonitor() {
        uninstallMenuKeyMonitor()
        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.isEmpty else { return event }
            switch event.keyCode {
            case UInt16(kVK_ANSI_X):
                self.closeMenu()
                return nil
            case UInt16(kVK_ANSI_C):
                self.copyUsage()
                return nil
            case UInt16(kVK_ANSI_R):
                self.refresh()
                return nil
            default:
                return event
            }
        }
    }

    func uninstallMenuKeyMonitor() {
        if let monitor = menuKeyMonitor {
            NSEvent.removeMonitor(monitor)
            menuKeyMonitor = nil
        }
    }

    @objc func noop() {}

    @objc func closeMenu() {
        menu.cancelTracking()
    }

    func showMenu() {
        guard let button = statusItem.button else { return }
        if needsMenuRebuild {
            rebuildMenu()
            needsMenuRebuild = false
        }
        button.performClick(nil)
    }

    // MARK: - Menu Building

    func buildMenu() {
        menu.removeAllItems()

        // Pinned usage items with rate sub-items (in canonical order)
        for key in allCategoryKeys {
            if pinnedKeys.contains(key), let item = usageItems[key] {
                menu.addItem(item)
                if let rateItem = rateItems[key] {
                    menu.addItem(rateItem)
                }
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(rateLimitItem)
        menu.addItem(updatedItem)

        let graphItem = NSMenuItem(title: "Usage Graph", action: #selector(showUsageGraph), keyEquivalent: "g")
        graphItem.target = self
        graphItem.keyEquivalentModifierMask = []
        menu.addItem(graphItem)

        let copyItem = NSMenuItem(title: "Copy Usage", action: #selector(copyUsage), keyEquivalent: "c")
        copyItem.target = self
        copyItem.keyEquivalentModifierMask = []
        menu.addItem(copyItem)

        let closeItem = NSMenuItem(title: "Close", action: #selector(closeMenu), keyEquivalent: "x")
        closeItem.target = self
        closeItem.keyEquivalentModifierMask = []
        menu.addItem(closeItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.keyEquivalentModifierMask = []
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem.separator())

        // Settings submenu — contains Refresh Interval, Notifications, More
        let settingsMenu = NSMenu()

        // Refresh Interval submenu
        let intervalMenu = NSMenu()
        interval1mItem = NSMenuItem(title: "Every 1 minute", action: #selector(setInterval1m), keyEquivalent: "")
        interval5mItem = NSMenuItem(title: "Every 5 minutes", action: #selector(setInterval5m), keyEquivalent: "")
        interval30mItem = NSMenuItem(title: "Every 30 minutes", action: #selector(setInterval30m), keyEquivalent: "")
        interval1hItem = NSMenuItem(title: "Every hour", action: #selector(setInterval1h), keyEquivalent: "")
        interval1mItem.target = self
        interval5mItem.target = self
        interval30mItem.target = self
        interval1hItem.target = self
        intervalMenu.addItem(interval1mItem)
        intervalMenu.addItem(interval5mItem)
        intervalMenu.addItem(interval30mItem)
        intervalMenu.addItem(interval1hItem)
        let intervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        settingsMenu.addItem(intervalItem)

        colorsItem = NSMenuItem(title: "Colors", action: #selector(toggleColors), keyEquivalent: "")
        colorsItem.target = self
        colorsItem.state = colorsEnabled ? .on : .off
        settingsMenu.addItem(colorsItem)

        rateInsightItem = NSMenuItem(title: "Rate Insight", action: #selector(toggleRateInsight), keyEquivalent: "")
        rateInsightItem.target = self
        rateInsightItem.state = rateInsightEnabled ? .on : .off
        settingsMenu.addItem(rateInsightItem)

        openAtLoginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        openAtLoginItem.target = self
        openAtLoginItem.state = openAtLoginEnabled ? .on : .off
        settingsMenu.addItem(openAtLoginItem)

        // Usage Source submenu
        let usageSourceMenu = NSMenu()
        usageSourceCookiesItem = NSMenuItem(title: "Use Desktop Cookies (recommended)", action: #selector(selectUsageSourceCookies), keyEquivalent: "")
        usageSourceCookiesItem.target = self
        usageSourceMenu.addItem(usageSourceCookiesItem)
        usageSourceOAuthItem = NSMenuItem(title: "Use OAuth API", action: #selector(selectUsageSourceOAuth), keyEquivalent: "")
        usageSourceOAuthItem.target = self
        usageSourceMenu.addItem(usageSourceOAuthItem)
        let usageSourceItem = NSMenuItem(title: "Usage Source", action: nil, keyEquivalent: "")
        usageSourceItem.submenu = usageSourceMenu
        settingsMenu.addItem(usageSourceItem)

        // Keyboard Shortcut submenu
        let hotkeyMenu = NSMenu()
        hotkeyCurrentItem = NSMenuItem(title: "Current: \(hotkeyDisplayString())", action: nil, keyEquivalent: "")
        hotkeyCurrentItem.isEnabled = false
        hotkeyMenu.addItem(hotkeyCurrentItem)
        hotkeyMenu.addItem(NSMenuItem.separator())
        hotkeyRecordItem = NSMenuItem(title: "Record New Shortcut...", action: #selector(recordHotkey), keyEquivalent: "")
        hotkeyRecordItem.target = self
        hotkeyMenu.addItem(hotkeyRecordItem)
        hotkeyRemoveItem = NSMenuItem(title: "Remove Shortcut", action: #selector(removeHotkey), keyEquivalent: "")
        hotkeyRemoveItem.target = self
        hotkeyRemoveItem.isEnabled = hotkeyKeyCode != UInt32.max
        hotkeyMenu.addItem(hotkeyRemoveItem)
        let hotkeyItem = NSMenuItem(title: "Keyboard Shortcut", action: nil, keyEquivalent: "")
        hotkeyItem.submenu = hotkeyMenu
        settingsMenu.addItem(hotkeyItem)

        // Notifications submenu
        let notifMenu = NSMenu()

        alert100Item = NSMenuItem(title: "100% Alert", action: #selector(toggleAlert100), keyEquivalent: "")
        alert100Item.target = self
        notifMenu.addItem(alert100Item)

        alertLimitItem = NSMenuItem(title: "Usage Limit Alert", action: #selector(toggleAlertLimit), keyEquivalent: "")
        alertLimitItem.target = self
        notifMenu.addItem(alertLimitItem)

        notifMenu.addItem(NSMenuItem.separator())

        // Reset Alarm submenu
        let alarmMenu = NSMenu()
        alarmAfter100Item = NSMenuItem(title: "After 100% session", action: #selector(setAlarmAfter100), keyEquivalent: "")
        alarmAfter100Item.target = self
        alarmMenu.addItem(alarmAfter100Item)

        alarmAfterUsedItem = NSMenuItem(title: "After any used session", action: #selector(setAlarmAfterUsed), keyEquivalent: "")
        alarmAfterUsedItem.target = self
        alarmMenu.addItem(alarmAfterUsedItem)

        alarmAfterAnyItem = NSMenuItem(title: "After any session", action: #selector(setAlarmAfterAny), keyEquivalent: "")
        alarmAfterAnyItem.target = self
        alarmMenu.addItem(alarmAfterAnyItem)

        alarmOffItem = NSMenuItem(title: "Off", action: #selector(setAlarmOff), keyEquivalent: "")
        alarmOffItem.target = self
        alarmMenu.addItem(alarmOffItem)

        alarmMenu.addItem(NSMenuItem.separator())

        alarmSkipItem = NSMenuItem(title: "Skip if previous was 0%", action: #selector(toggleAlarmSkip), keyEquivalent: "")
        alarmSkipItem.target = self
        alarmMenu.addItem(alarmSkipItem)

        let alarmItem = NSMenuItem(title: "Reset Alarm", action: nil, keyEquivalent: "")
        alarmItem.submenu = alarmMenu
        notifMenu.addItem(alarmItem)

        notifMenu.addItem(NSMenuItem.separator())

        // Sound submenu
        let soundMenu = NSMenu()
        soundItems.removeAll()
        let soundNames = ["Tink", "Pop", "Purr", "Funk", "Glass", "Ping", "Morse"]
        for name in soundNames {
            let item = NSMenuItem(title: name, action: #selector(selectSound(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            soundMenu.addItem(item)
            soundItems.append(item)
        }
        let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        soundItem.submenu = soundMenu
        notifMenu.addItem(soundItem)

        let notifItem = NSMenuItem(title: "Notifications", action: nil, keyEquivalent: "")
        notifItem.submenu = notifMenu
        settingsMenu.addItem(notifItem)

        // More submenu — all categories with checkmark = pinned
        moreMenu = NSMenu()
        moreToggleItems.removeAll()
        for key in allCategoryKeys {
            let label = categoryLabels[key] ?? key
            let item = NSMenuItem(title: label, action: #selector(togglePin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = pinnedKeys.contains(key) ? .on : .off
            moreMenu.addItem(item)
            moreToggleItems[key] = item
        }
        let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        moreItem.submenu = moreMenu
        settingsMenu.addItem(moreItem)

        // Debug Mode submenu — copy latest request/response as formatted JSON or as a curl command
        let debugMenu = NSMenu()
        let debugRequestItem = NSMenuItem(title: "Request", action: #selector(copyDebugRequest), keyEquivalent: "")
        debugRequestItem.target = self
        debugMenu.addItem(debugRequestItem)
        let debugResponseItem = NSMenuItem(title: "Response", action: #selector(copyDebugResponse), keyEquivalent: "")
        debugResponseItem.target = self
        debugMenu.addItem(debugResponseItem)
        let debugCurlItem = NSMenuItem(title: "curl", action: #selector(copyDebugCurl), keyEquivalent: "")
        debugCurlItem.target = self
        debugMenu.addItem(debugCurlItem)
        let debugItem = NSMenuItem(title: "Debug Mode", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        settingsMenu.addItem(debugItem)

        let exportItem = NSMenuItem(title: "Export Data...", action: #selector(exportData), keyEquivalent: "")
        exportItem.target = self
        settingsMenu.addItem(exportItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        // Help submenu
        let helpMenu = NSMenu()

        let claudeUsageItem = NSMenuItem(title: "Claude Usage", action: #selector(openClaudeUsage), keyEquivalent: "")
        claudeUsageItem.target = self
        helpMenu.addItem(claudeUsageItem)

        let apiUsageItem = NSMenuItem(title: "API Usage", action: #selector(openAPIUsage), keyEquivalent: "")
        apiUsageItem.target = self
        helpMenu.addItem(apiUsageItem)

        let githubItem = NSMenuItem(title: "GitHub", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        helpMenu.addItem(githubItem)

        let authorItem = NSMenuItem(title: "Author", action: #selector(openAuthor), keyEquivalent: "")
        authorItem.target = self
        helpMenu.addItem(authorItem)

        helpMenu.addItem(NSMenuItem.separator())

        let shareItem = NSMenuItem(title: "Share...", action: #selector(shareApp), keyEquivalent: "")
        shareItem.target = self
        helpMenu.addItem(shareItem)

        let updateItem = NSMenuItem(title: "Update…", action: #selector(openUpdateDocs), keyEquivalent: "")
        updateItem.target = self
        helpMenu.addItem(updateItem)

        helpMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        helpMenu.addItem(quitItem)

        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        menu.addItem(helpMenuItem)

        // Restore checkmark states
        updateIntervalMenu()
        updateNotificationMenu()
        updateAlarmMenu()
        updateSoundMenu()
    }

    func rebuildMenu() {
        buildMenu()
    }

    // MARK: - Sleep/Wake

    @objc func handleSleep() {
        timer?.invalidate()
        timer = nil
        alarmCheckTimer?.invalidate()
        alarmCheckTimer = nil
    }

    @objc func handleWake() {
        restartTimer()
        refresh()
    }

    // MARK: - Menu Updates

    func updateIntervalMenu() {
        interval1mItem?.state = refreshInterval == 60 ? .on : .off
        interval5mItem?.state = refreshInterval == 300 ? .on : .off
        interval30mItem?.state = refreshInterval == 1800 ? .on : .off
        interval1hItem?.state = refreshInterval == 3600 ? .on : .off
    }

    func updateNotificationMenu() {
        alert100Item?.state = alert100Enabled ? .on : .off
        alertLimitItem?.state = alertLimitEnabled ? .on : .off
    }

    func updateAlarmMenu() {
        alarmAfter100Item?.state = alarmCondition == 1 ? .on : .off
        alarmAfterUsedItem?.state = alarmCondition == 2 ? .on : .off
        alarmAfterAnyItem?.state = alarmCondition == 3 ? .on : .off
        alarmOffItem?.state = alarmCondition == 0 ? .on : .off
        alarmSkipItem?.state = alarmSkipIfPrevZero ? .on : .off
    }

    func updateSoundMenu() {
        for item in soundItems {
            if let name = item.representedObject as? String {
                item.state = name == selectedSoundName ? .on : .off
            }
        }
    }

    func updateUsageSourceMenu() {
        usageSourceCookiesItem?.state = usageSource == 0 ? .on : .off
        usageSourceOAuthItem?.state = usageSource == 1 ? .on : .off
    }

    func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = max(10, refreshInterval * 0.1)
    }

    // MARK: - Actions

    @objc func setInterval1m() { refreshInterval = 60 }
    @objc func setInterval5m() { refreshInterval = 300 }
    @objc func setInterval30m() { refreshInterval = 1800 }
    @objc func setInterval1h() { refreshInterval = 3600 }

    @objc func toggleAlert100() {
        alert100Enabled = !alert100Enabled
        updateNotificationMenu()
    }

    @objc func toggleAlertLimit() {
        alertLimitEnabled = !alertLimitEnabled
        updateNotificationMenu()
    }

    @objc func setAlarmAfter100() { alarmCondition = 1 }
    @objc func setAlarmAfterUsed() { alarmCondition = 2 }
    @objc func setAlarmAfterAny() { alarmCondition = 3 }
    @objc func setAlarmOff() { alarmCondition = 0 }

    @objc func toggleAlarmSkip() {
        alarmSkipIfPrevZero = !alarmSkipIfPrevZero
        updateAlarmMenu()
    }

    @objc func toggleColors() {
        colorsEnabled = !colorsEnabled
        refresh()
    }

    @objc func toggleRateInsight() {
        rateInsightEnabled = !rateInsightEnabled
        if rateInsightEnabled { refresh() }
    }

    @objc func showUsageGraph() {
        if let existing = graphPanel {
            existing.close()
            graphPanel = nil
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 220),
            styleMask: [.titled, .closable, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Claude Usage — Last 90 Days"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.center()

        let webView = WKWebView(frame: panel.contentView!.bounds)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        panel.contentView?.addSubview(webView)

        let html = generateHeatmapHTML()
        webView.loadHTMLString(html, baseURL: nil)

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        graphPanel = panel
    }

    @objc func recordHotkey() {
        // Temporarily become a regular app so the alert window can receive focus
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Record Keyboard Shortcut"
        alert.informativeText = "Press your desired key combination.\nUse at least one modifier (Cmd, Shift, Opt, Ctrl) plus a key."
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        // Set the app icon on the alert
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            alert.icon = NSImage(contentsOfFile: iconPath)
        }

        // Add a label to show what's being pressed
        let label = NSTextField(labelWithString: "Waiting for shortcut...")
        label.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        alert.accessoryView = label

        // Capture key events on the alert window
        var captured = false
        var capturedKeyCode: UInt32 = 0
        var capturedModifiers: UInt32 = 0

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require at least one modifier
            if mods.contains(.command) || mods.contains(.option) || mods.contains(.control) {
                let app = NSApplication.shared.delegate as! AppDelegate
                capturedKeyCode = UInt32(event.keyCode)
                capturedModifiers = app.carbonModifiers(from: mods)
                captured = true
                label.stringValue = app.hotkeyDisplayStringFor(keyCode: capturedKeyCode, modifiers: capturedModifiers)
                // Close the alert
                alert.buttons.first?.performClick(nil)
                return nil
            }
            label.stringValue = "Add a modifier key (Cmd, Opt, Ctrl)"
            return nil
        }

        alert.runModal()

        // Restore accessory mode (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }

        if captured {
            unregisterGlobalHotkey()
            hotkeyKeyCode = capturedKeyCode
            hotkeyModifiers = capturedModifiers
            saveHotkeyPrefs()
            registerGlobalHotkey()
        }
    }

    @objc func removeHotkey() {
        unregisterGlobalHotkey()
        hotkeyKeyCode = UInt32.max
        hotkeyModifiers = 0
        saveHotkeyPrefs()
        updateHotkeyMenu()
    }

    func hotkeyDisplayStringFor(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Opt") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined(separator: "+")
    }

    @objc func toggleOpenAtLogin() {
        openAtLoginEnabled = !openAtLoginEnabled
    }

    @objc func selectUsageSourceCookies() {
        usageSource = 0
    }

    @objc func selectUsageSourceOAuth() {
        usageSource = 1
    }

    func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if openAtLoginEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {}
        }
    }

    @objc func selectSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        selectedSoundName = name
        playClicks(count: 2, soundName: name)
    }

    @objc func togglePin(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        suppressRebuild = true
        if pinnedKeys.contains(key) {
            pinnedKeys.remove(key)
        } else {
            pinnedKeys.insert(key)
        }
        suppressRebuild = false
        sender.state = pinnedKeys.contains(key) ? .on : .off
        needsMenuRebuild = true
    }

    @objc func openClaudeUsage() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openAPIUsage() {
        if let url = URL(string: "https://platform.claude.com/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openGitHub() {
        if let url = URL(string: "https://github.com/asboyer/claude-usage-swift") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openUpdateDocs() {
        if let url = URL(string: "https://github.com/asboyer/claude-usage-swift#updating") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openAuthor() {
        if let url = URL(string: "https://asboyer.com") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func shareApp() {
        guard let button = statusItem.button else { return }
        let text = "Claude Usage Tracker - a macOS menu bar app that tracks your Claude usage limits"
        let url = URL(string: "https://github.com/asboyer/claude-usage-swift")!
        let picker = NSSharingServicePicker(items: [text, url])
        picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc func copyUsage() {
        let lines = allCategoryKeys
            .filter { pinnedKeys.contains($0) }
            .compactMap { usageItems[$0]?.title }
        let text = (lines + [updatedItem.title]).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func copyDebugRequest() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastRequestForDebug ?? "", forType: .string)
    }

    @objc func copyDebugResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastResponseForDebug ?? "", forType: .string)
    }

    @objc func copyDebugCurl() {
        let ua = lastUserAgentForDebug ?? "curl/8.4.0"
        let script = """
CC_TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import sys, json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])")
curl -sS 'https://api.anthropic.com/api/oauth/usage' \\
  -H "Authorization: Bearer $CC_TOKEN" \\
  -H "anthropic-beta: oauth-2025-04-20" \\
  -H "User-Agent: \(ua)"
"""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(script, forType: .string)
    }

    @objc func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "claude_usage_history.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        panel.begin { response in
            defer { NSApp.setActivationPolicy(.accessory) }
            guard response == .OK, let url = panel.url else { return }

            let file = loadHistoryFile()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(file) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Refresh & Update

    @objc func refresh() {
        if !hasData {
            statusItem.button?.title = "..."
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let strongSelf = self else { return }
            let source = strongSelf.usageSource

            if source == 0 {
                // Prefer Claude Desktop cookie-based usage API when available, with OAuth fallback.
                fetchUsageViaClaudeDesktopCookies { usage in
                    if let usage = usage {
                        DispatchQueue.main.async {
                            self?.updateUI(usage: usage, rateLimited: false)
                        }
                        return
                    }

                    guard let token = getOAuthToken() else {
                        DispatchQueue.main.async {
                            self?.hasData = false
                            self?.statusItem.button?.title = "..."
                        }
                        return
                    }

                    fetchUsage(token: token) { usage, rateLimited in
                        DispatchQueue.main.async {
                            self?.updateUI(usage: usage, rateLimited: rateLimited)
                        }
                    }
                }
            } else {
                // OAuth only
                guard let token = getOAuthToken() else {
                    DispatchQueue.main.async {
                        self?.hasData = false
                        self?.statusItem.button?.title = "..."
                    }
                    return
                }

                fetchUsage(token: token) { usage, rateLimited in
                    DispatchQueue.main.async {
                        self?.updateUI(usage: usage, rateLimited: rateLimited)
                    }
                }
            }
        }
    }

    func tabbedMenuItemString(_ label: String, _ detail: String, color: NSColor? = nil) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 140, options: [:])]
        let full = "\(label)\t\(detail)"
        return NSAttributedString(string: full, attributes: [
            .paragraphStyle: paragraph,
            .font: NSFont.menuFont(ofSize: 14),
            .foregroundColor: color ?? NSColor.labelColor
        ])
    }

    /// Projection-based color: "if I keep this average pace, what % will I hit at window end?"
    /// Smooth hue interpolation from green (under budget) through yellow/orange to red (overshooting).
    func severityColor(utilization: Double, resetsAt: String?, windowSeconds: TimeInterval) -> NSColor? {
        guard colorsEnabled, utilization > 0 else { return nil }
        if utilization >= 100 {
            return NSColor(calibratedHue: 0, saturation: 0.8, brightness: 1.0, alpha: 1.0)
        }

        guard let resetStr = resetsAt,
              let resetDate = isoFormatter.date(from: resetStr) ?? isoFormatterNoFrac.date(from: resetStr) else {
            return nil
        }

        let remaining = max(resetDate.timeIntervalSince(Date()), 0)
        let elapsedFraction = max((windowSeconds - remaining) / windowSeconds, 0.10)
        let projected = utilization / elapsedFraction

        // Smooth hue interpolation based on projected end-of-window utilization.
        //   projected <= 80  → hue 120° (green)
        //   80–105           → 120°→55° (green to yellow)
        //   105–140          → 55°→15° (yellow to orange)
        //   > 140            → 0° (red)
        var hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat

        if projected <= 80 {
            hue = 120.0 / 360.0
            saturation = 0.8; brightness = 1.0
        } else if projected <= 105 {
            let t = CGFloat((projected - 80) / 25.0)
            hue = CGFloat(120.0 - 65.0 * Double(t)) / 360.0
            saturation = 0.8 + 0.05 * t; brightness = 1.0
        } else if projected <= 140 {
            let t = CGFloat((projected - 105) / 35.0)
            hue = CGFloat(55.0 - 40.0 * Double(t)) / 360.0
            saturation = 0.85 + 0.05 * t; brightness = 1.0 - 0.1 * t
        } else {
            hue = 0; saturation = 0.9; brightness = 0.9
        }

        // Absolute utilization overrides (tighten only, never relax)
        if utilization >= 90 { hue = min(hue, 25.0 / 360.0) }
        else if utilization >= 80 { hue = min(hue, 55.0 / 360.0) }

        return NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    }

    func dimmedMenuItemString(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    func updateRateItem(key: String, utilization: Double, isWeekly: Bool) {
        guard let item = rateItems[key] else { return }
        guard rateInsightEnabled else {
            item.isHidden = true
            return
        }
        let rate = rateForCategory(key, currentUtil: utilization, isWeekly: isWeekly)
        guard let value = isWeekly ? rate.perDay : rate.perHour else {
            item.isHidden = true
            return
        }

        let unitLabel = isWeekly ? "day" : "hr"
        let rateText = String(format: "  %.0f%%/%@", value, unitLabel)
        let title = "\(rateText) · \(rate.descriptor)"
        let color = colorsEnabled ? rateDescriptorColor(rate.descriptor) : NSColor.secondaryLabelColor

        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 12),
            .foregroundColor: color
        ])
        item.title = title
        item.isHidden = false
    }

    func updateUsageItem(key: String, limit: UsageLimit?, windowSeconds: TimeInterval = 0) {
        guard let item = usageItems[key] else { return }
        let label = categoryLabels[key] ?? key
        if let l = limit {
            let pct = Int(l.utilization)
            let reset = l.resets_at.map { formatReset($0) } ?? "--"
            item.title = "\(label): \(pct)% (resets \(reset))"
            let color = windowSeconds > 0
                ? severityColor(utilization: l.utilization, resetsAt: l.resets_at, windowSeconds: windowSeconds)
                : nil
            item.attributedTitle = tabbedMenuItemString("\(label): \(pct)%", "resets \(reset)", color: color)

            let isWeekly = key != "five_hour"
            recordUsageSample(key, utilization: l.utilization)
            updateRateItem(key: key, utilization: l.utilization, isWeekly: isWeekly)
        } else {
            item.title = "\(label): --"
            item.attributedTitle = nil
            rateItems[key]?.isHidden = true
        }
    }

    func updateUI(usage: UsageResponse?, rateLimited: Bool = false) {
        isRateLimited = rateLimited
        rateLimitItem?.isHidden = !rateLimited
        if rateLimited {
            rateLimitItem?.attributedTitle = NSAttributedString(
                string: "Rate limited. Try again later.",
                attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 14)]
            )
        }

        guard let usage = usage else {
            hasData = false
            statusItem.button?.title = "..."
            return
        }

        lastFetchDate = Date()

        // Update all limit-based categories
        updateUsageItem(key: "five_hour", limit: usage.five_hour, windowSeconds: 5 * 3600)
        updateUsageItem(key: "seven_day", limit: usage.seven_day, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_opus", limit: usage.seven_day_opus, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_sonnet", limit: usage.seven_day_sonnet, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_oauth_apps", limit: usage.seven_day_oauth_apps, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_cowork", limit: usage.seven_day_cowork, windowSeconds: 7 * 86400)

        // Extra usage (special format — monthly window, so treat as weekly-style for rate)
        if let e = usage.extra_usage, e.is_enabled,
           let used = e.used_credits, let limit = e.monthly_limit, let util = e.utilization {
            let extraText = String(format: "Extra: $%.2f/$%.0f", used / 100, limit / 100)
            let extraDetail = String(format: "%.0f%%", util)
            usageItems["extra_usage"]?.title = String(format: "Extra: $%.2f/$%.0f (%.0f%%)", used / 100, limit / 100, util)
            usageItems["extra_usage"]?.attributedTitle = tabbedMenuItemString(extraText, extraDetail)
            recordUsageSample("extra_usage", utilization: util)
            updateRateItem(key: "extra_usage", utilization: util, isWeekly: true)
        } else {
            usageItems["extra_usage"]?.title = "Extra: --"
            usageItems["extra_usage"]?.attributedTitle = nil
            rateItems["extra_usage"]?.isHidden = true
        }

        // 5-hour specific: reset date, transitions, menu bar title
        if let h = usage.five_hour {
            let pct = Int(h.utilization)
            let reset = h.resets_at.map { formatReset($0) } ?? "--"

            if let resetStr = h.resets_at {
                let parsedDate = isoFormatter.date(from: resetStr) ?? isoFormatterNoFrac.date(from: resetStr)

                if let newResetDate = parsedDate {
                    if let lastReset = lastKnownResetDate,
                       abs(newResetDate.timeIntervalSince(lastReset)) > 60 {
                        triggerAlarmIfNeeded(endedSessionUtil: lastSessionFinalUtil)
                    }
                    lastKnownResetDate = newResetDate
                    scheduleAlarmCheckTimer(for: newResetDate)
                }
            }

            let newUtil = h.utilization
            if previousFiveHourUtil >= 0 && previousFiveHourUtil < 100 && newUtil >= 100 {
                if alert100Enabled {
                    playClicks(count: 2, soundName: selectedSoundName)
                }
            }
            lastSessionFinalUtil = newUtil
            previousSessionHadUsage = newUtil > 0
            previousFiveHourUtil = newUtil

            let excl = alarmCondition != 0 ? "!" : ""
            if pct >= 100 {
                if let e = usage.extra_usage, e.is_enabled, let spent = e.used_credits {
                    let dollars = spent / 100
                    currentPct = String(format: "$%.2f%@", dollars, excl)
                } else {
                    currentPct = "\(reset)\(excl)"
                }
            } else {
                currentPct = "\(pct)%"
            }

            hasData = true
            statusItem.length = NSStatusItem.variableLength
            statusItem.button?.title = currentPct
        }

        // Extra usage transition detection
        if let e = usage.extra_usage, let util = e.utilization {
            if previousExtraUtil >= 0 && previousExtraUtil < 100 && util >= 100 {
                if alertLimitEnabled {
                    playClicks(count: 3, soundName: selectedSoundName)
                }
            }
            previousExtraUtil = util
        }

        // Updated time
        let stale = isDataStale() ? " (stale)" : ""
        let updatedText = "Updated: \(timeFormatter.string(from: Date()))\(stale)"
        updatedItem.title = updatedText
        updatedItem.attributedTitle = dimmedMenuItemString(updatedText)
    }

    func isDataStale() -> Bool {
        guard let last = lastFetchDate else { return false }
        return Date().timeIntervalSince(last) > refreshInterval * 2
    }

    // MARK: - Alarm Logic

    func scheduleAlarmCheckTimer(for resetDate: Date) {
        alarmCheckTimer?.invalidate()
        let fireDate = resetDate.addingTimeInterval(1)
        let delay = fireDate.timeIntervalSinceNow
        guard delay > 0 else { return }
        alarmCheckTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }

    func triggerAlarmIfNeeded(endedSessionUtil: Double) {
        guard alarmCondition != 0 else { return }
        if alarmSkipIfPrevZero && !previousSessionHadUsage { return }

        var shouldAlarm = false
        switch alarmCondition {
        case 1: shouldAlarm = endedSessionUtil >= 100
        case 2: shouldAlarm = endedSessionUtil > 0
        case 3: shouldAlarm = true
        default: break
        }

        guard shouldAlarm else { return }
        guard !alarmIsPlaying else { return }

        alarmIsPlaying = true
        playAlarmBursts(soundName: selectedSoundName, checkMuted: { false }) { [weak self] in
            self?.alarmIsPlaying = false
        }
    }
}

