import Foundation

// MARK: - Cursor usage (Cursor dashboard API)

/// The two included-usage buckets Cursor meters separately, plus the billing cycle they reset on.
struct CursorUsage {
    let cursorModelsPercent: Double
    let otherModelsPercent: Double
    let cycleEndsAt: Date?
    let cycleSeconds: TimeInterval

    /// The bucket closest to its limit, which is the one worth putting in the menu bar.
    var highestPercent: Double {
        return max(cursorModelsPercent, otherModelsPercent)
    }
}

/// Shape returned by `POST /aiserver.v1.DashboardService/GetCurrentPeriodUsage`.
/// Connect encodes 64-bit fields as strings, so the cycle bounds arrive as decimal milliseconds.
private struct CursorAPIUsageResponse: Codable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let planUsage: PlanUsage?

    struct PlanUsage: Codable {
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
    }
}

/// Last Cursor request/response for Debug Mode copy.
var lastCursorRequestForDebug: String?
var lastCursorResponseForDebug: String?

private let cursorKeychainAccount = "cursor-user"
private let cursorKeychainService = "cursor-access-token"

/// Reads the token the Cursor CLI stores in the login keychain.
///
/// The CLI writes the item by shelling out to `/usr/bin/security`, so reading it back the same way
/// inherits the access already granted to that binary. Calling the Security framework directly from
/// this app would be a different caller and would prompt for keychain access on every launch.
func getCursorAccessToken() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = [
        "find-generic-password", "-a", cursorKeychainAccount, "-s", cursorKeychainService, "-w",
    ]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()

    do {
        try process.run()
    } catch {
        return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else { return nil }
    let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let token, !token.isEmpty else { return nil }
    return token
}

private func date(fromMilliseconds string: String?) -> Date? {
    guard let string, let milliseconds = Double(string) else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
}

private func usage(from response: CursorAPIUsageResponse) -> CursorUsage? {
    guard let planUsage = response.planUsage else { return nil }
    let cycleStart = date(fromMilliseconds: response.billingCycleStart)
    let cycleEnd = date(fromMilliseconds: response.billingCycleEnd)
    let cycleSeconds =
        (cycleStart != nil && cycleEnd != nil)
        ? cycleEnd!.timeIntervalSince(cycleStart!)
        : 0

    // A bucket with no spend this cycle is omitted from the response rather than sent as zero.
    return CursorUsage(
        cursorModelsPercent: planUsage.autoPercentUsed ?? 0,
        otherModelsPercent: planUsage.apiPercentUsed ?? 0,
        cycleEndsAt: cycleEnd,
        cycleSeconds: cycleSeconds
    )
}

/// Fetches Cursor usage from the same dashboard endpoint the Cursor client uses.
/// Cursor records no usage snapshot on disk, so there is no offline fallback.
func fetchCursorUsage(completion: @escaping (CursorUsage?) -> Void) {
    guard
        let token = getCursorAccessToken(),
        let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")
    else {
        completion(nil)
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
    request.httpBody = Data("{}".utf8)

    let requestDict: [String: Any] = [
        "url": url.absoluteString,
        "method": "POST",
        "headers": [
            "Authorization": "Bearer ***",
            "Content-Type": "application/json",
            "connect-protocol-version": "1",
        ],
        "body": "{}",
    ]
    if let requestData = try? JSONSerialization.data(withJSONObject: requestDict, options: [.prettyPrinted]) {
        lastCursorRequestForDebug = String(data: requestData, encoding: .utf8)
    }

    URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
        guard let data, let httpResponse = response as? HTTPURLResponse else {
            completion(nil)
            return
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted)
        {
            lastCursorResponseForDebug = String(data: prettyData, encoding: .utf8)
        } else {
            lastCursorResponseForDebug = String(data: data, encoding: .utf8)
        }

        guard
            (200..<300).contains(httpResponse.statusCode),
            let decoded = try? JSONDecoder().decode(CursorAPIUsageResponse.self, from: data)
        else {
            completion(nil)
            return
        }
        completion(usage(from: decoded))
    }.resume()
}
