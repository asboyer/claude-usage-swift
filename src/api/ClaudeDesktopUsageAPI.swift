import CommonCrypto
import Foundation
import Security
import SQLite3

// MARK: - Claude Desktop cookie-based usage (claude-web-usage strategy)

private func getClaudeDesktopEncryptionKey() -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Safe Storage",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard
        status == errSecSuccess,
        let passwordData = result as? Data,
        !passwordData.isEmpty
    else {
        return nil
    }

    // Chromium-style PBKDF2(password, "saltysalt", 1003, 16, SHA1).
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
    // Expect Chromium "v10" prefix.
    guard encrypted.count > 3, String(data: encrypted.prefix(3), encoding: .utf8) == "v10" else {
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
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }

    if sqlite3_step(statement) == SQLITE_ROW, let blobPtr = sqlite3_column_blob(statement, 0) {
        let size = Int(sqlite3_column_bytes(statement, 0))
        let data = Data(bytes: blobPtr, count: size)
        return decryptClaudeCookie(data, key: key)
    }
    return nil
}

func fetchUsageViaClaudeDesktopCookies(completion: @escaping (UsageResponse?) -> Void) {
    guard let key = getClaudeDesktopEncryptionKey() else {
        completion(nil)
        return
    }
    guard let sessionKey = getClaudeCookie(name: "sessionKey", key: key),
          let orgID = getClaudeCookie(name: "lastActiveOrg", key: key) else {
        completion(nil)
        return
    }

    guard let url = URL(string: "https://claude.ai/api/organizations/\(orgID)/usage") else {
        completion(nil)
        return
    }

    var request = URLRequest(url: url)
    request.setValue("sessionKey=\(sessionKey); lastActiveOrg=\(orgID)", forHTTPHeaderField: "Cookie")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        forHTTPHeaderField: "User-Agent"
    )

    // Debug mode: record a sanitized request description.
    let requestDict: [String: Any] = [
        "url": url.absoluteString,
        "method": "GET",
        "headers": [
            "Cookie": "sessionKey=***; lastActiveOrg=\(orgID)",
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        ],
    ]
    if let requestData = try? JSONSerialization.data(withJSONObject: requestDict, options: [.prettyPrinted]) {
        lastRequestForDebug = String(data: requestData, encoding: .utf8)
    }

    URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
        guard let data else {
            completion(nil)
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

        guard let httpResponse = response as? HTTPURLResponse else {
            completion(nil)
            return
        }
        guard
            (200..<300).contains(httpResponse.statusCode),
            let usage = try? JSONDecoder().decode(UsageResponse.self, from: data)
        else {
            completion(nil)
            return
        }
        completion(usage)
    }.resume()
}
