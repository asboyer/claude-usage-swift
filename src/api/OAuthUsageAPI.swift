import Foundation
import Security

private let userAgents: [String] = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:120.0) Gecko/20100101 Firefox/120.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0",
    "curl/8.4.0",
]
private var userAgentIndex = 0

/// Last request/response from usage fetch for Debug Mode copy.
var lastRequestForDebug: String?
var lastResponseForDebug: String?
var lastUserAgentForDebug: String?

func getOAuthToken() -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard
        status == errSecSuccess,
        let data = result as? Data,
        let json = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
        let jsonData = json.data(using: .utf8),
        let credentials = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
        let oauth = credentials["claudeAiOauth"] as? [String: Any],
        let token = oauth["accessToken"] as? String
    else {
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
            "User-Agent": userAgent,
        ],
    ]
    if let requestData = try? JSONSerialization.data(withJSONObject: requestDict, options: [.prettyPrinted]) {
        lastRequestForDebug = String(data: requestData, encoding: .utf8)
    }

    URLSession(configuration: .ephemeral).dataTask(with: request) { data, _, _ in
        guard let data else {
            completion(nil, false)
            return
        }
        if
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
            let prettyString = String(data: prettyData, encoding: .utf8)
        {
            lastResponseForDebug = prettyString
        } else {
            lastResponseForDebug = String(data: data, encoding: .utf8)
        }

        if
            let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
            errorResponse.error?.type == "rate_limit_error"
        {
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
