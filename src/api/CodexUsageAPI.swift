import Foundation

// MARK: - Codex usage (ChatGPT backend API, with local session fallback)

enum CodexUsageSource: String {
    case api
    case localSession
}

struct CodexUsage {
    let weekly: CodexRateWindow?
    let planType: String?
    let source: CodexUsageSource
}

/// Shape returned by `GET /backend-api/wham/usage`.
private struct CodexAPIUsageResponse: Codable {
    let plan_type: String?
    let rate_limit: RateLimit?

    struct RateLimit: Codable {
        let primary_window: Window?
        let secondary_window: Window?
    }

    struct Window: Codable {
        let used_percent: Double?
        let limit_window_seconds: Double?
        let reset_at: Double?
        let reset_after_seconds: Double?
    }
}

/// Shape of the `rate_limits` payload Codex CLI writes into session rollout files.
private struct CodexSessionRateLimits: Codable {
    let primary: Window?
    let secondary: Window?
    let plan_type: String?

    struct Window: Codable {
        let used_percent: Double?
        let window_minutes: Double?
        let resets_at: Double?
        let resets_in_seconds: Double?
    }
}

/// Last Codex request/response for Debug Mode copy.
var lastCodexRequestForDebug: String?
var lastCodexResponseForDebug: String?

private func codexHomeDirectory() -> URL {
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["CODEX_HOME"], !override.isEmpty {
        return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
}

func getCodexAccessToken() -> String? {
    let authURL = codexHomeDirectory().appendingPathComponent("auth.json")
    guard
        let data = try? Data(contentsOf: authURL),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let tokens = json["tokens"] as? [String: Any],
        let token = tokens["access_token"] as? String,
        !token.isEmpty
    else {
        return nil
    }
    return token
}

private func window(from apiWindow: CodexAPIUsageResponse.Window?) -> CodexRateWindow? {
    guard let apiWindow, let usedPercent = apiWindow.used_percent else { return nil }
    let resetDate = apiWindow.reset_at.map { Date(timeIntervalSince1970: $0) }
        ?? apiWindow.reset_after_seconds.map { Date(timeIntervalSinceNow: $0) }
    return CodexRateWindow(
        usedPercent: usedPercent,
        windowSeconds: apiWindow.limit_window_seconds ?? 0,
        resetsAt: resetDate
    )
}

private func window(from sessionWindow: CodexSessionRateLimits.Window?) -> CodexRateWindow? {
    guard let sessionWindow, let usedPercent = sessionWindow.used_percent else { return nil }
    let resetDate = sessionWindow.resets_at.map { Date(timeIntervalSince1970: $0) }
        ?? sessionWindow.resets_in_seconds.map { Date(timeIntervalSinceNow: $0) }
    return CodexRateWindow(
        usedPercent: usedPercent,
        windowSeconds: (sessionWindow.window_minutes ?? 0) * 60,
        resetsAt: resetDate
    )
}

/// Fetches Codex usage from the ChatGPT backend, falling back to the most recent
/// local Codex session when no token is present or the token has expired.
func fetchCodexUsage(completion: @escaping (CodexUsage?) -> Void) {
    guard
        let token = getCodexAccessToken(),
        let url = URL(string: "https://chatgpt.com/backend-api/wham/usage")
    else {
        completion(readCodexUsageFromLocalSessions())
        return
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let requestDict: [String: Any] = [
        "url": url.absoluteString,
        "method": "GET",
        "headers": [
            "Authorization": "Bearer ***",
            "Accept": "application/json",
        ],
    ]
    if let requestData = try? JSONSerialization.data(withJSONObject: requestDict, options: [.prettyPrinted]) {
        lastCodexRequestForDebug = String(data: requestData, encoding: .utf8)
    }

    URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
        guard let data, let httpResponse = response as? HTTPURLResponse else {
            completion(readCodexUsageFromLocalSessions())
            return
        }

        if
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
        {
            lastCodexResponseForDebug = String(data: prettyData, encoding: .utf8)
        } else {
            lastCodexResponseForDebug = String(data: data, encoding: .utf8)
        }

        guard
            (200..<300).contains(httpResponse.statusCode),
            let usage = try? JSONDecoder().decode(CodexAPIUsageResponse.self, from: data)
        else {
            // Expired or rejected credentials still leave usable data on disk.
            completion(readCodexUsageFromLocalSessions())
            return
        }

        let weekly = CodexWindowSelector.selectWeekly(
            primary: window(from: usage.rate_limit?.primary_window),
            secondary: window(from: usage.rate_limit?.secondary_window)
        )
        guard weekly != nil else {
            completion(readCodexUsageFromLocalSessions())
            return
        }
        completion(CodexUsage(weekly: weekly, planType: usage.plan_type, source: .api))
    }.resume()
}

// MARK: - Local session fallback

private let maxSessionFilesToScan = 3

/// Reads the newest `rate_limits` payload Codex CLI recorded in its session rollout files.
func readCodexUsageFromLocalSessions() -> CodexUsage? {
    let sessionsDirectory = codexHomeDirectory().appendingPathComponent("sessions")
    let fileManager = FileManager.default
    guard
        let enumerator = fileManager.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
    else {
        return nil
    }

    var candidates: [(url: URL, modified: Date)] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
        let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        candidates.append((fileURL, modified))
    }

    let newestFirst = candidates.sorted { $0.modified > $1.modified }.prefix(maxSessionFilesToScan)
    for candidate in newestFirst {
        if let usage = readCodexUsage(fromSessionFile: candidate.url) {
            return usage
        }
    }
    return nil
}

private func readCodexUsage(fromSessionFile url: URL) -> CodexUsage? {
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }

    for line in contents.split(separator: "\n").reversed() {
        guard line.contains("\"rate_limits\"") else { continue }
        guard
            let lineData = line.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
            let payload = root["payload"] as? [String: Any],
            let rateLimits = payload["rate_limits"],
            let rateLimitsData = try? JSONSerialization.data(withJSONObject: rateLimits),
            let decoded = try? JSONDecoder().decode(CodexSessionRateLimits.self, from: rateLimitsData)
        else {
            continue
        }

        let weekly = CodexWindowSelector.selectWeekly(
            primary: window(from: decoded.primary),
            secondary: window(from: decoded.secondary)
        )
        guard let weekly else { continue }
        return CodexUsage(weekly: weekly, planType: decoded.plan_type, source: .localSession)
    }
    return nil
}
