import XCTest

@testable import ClaudeUsageCore

final class KeychainCredentialsTests: XCTestCase {
    func testReturnsTrimmedPasswordOnSuccess() {
        var captured: [String] = []
        let password = keychainPassword(service: "Claude Code-credentials") { arguments in
            captured = arguments
            return (0, Data("{\"claudeAiOauth\":{}}\n".utf8))
        }

        XCTAssertEqual(password, "{\"claudeAiOauth\":{}}")
        XCTAssertEqual(captured, ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
    }

    func testPassesAccountWhenGiven() {
        var captured: [String] = []
        _ = keychainPassword(service: "cursor-access-token", account: "cursor-user") { arguments in
            captured = arguments
            return (0, Data("token".utf8))
        }

        XCTAssertEqual(
            captured,
            ["find-generic-password", "-s", "cursor-access-token", "-a", "cursor-user", "-w"]
        )
    }

    func testReturnsNilWhenItemNotFound() {
        // `security` exits 44 (errSecItemNotFound) and writes nothing.
        let password = keychainPassword(service: "no-such-service") { _ in (44, Data()) }

        XCTAssertNil(password)
    }

    func testReturnsNilWhenPasswordIsBlank() {
        let password = keychainPassword(service: "Claude Safe Storage") { _ in (0, Data("\n".utf8)) }

        XCTAssertNil(password)
    }

    func testReturnsNilWhenSecurityCannotLaunch() {
        let password = keychainPassword(service: "Claude Safe Storage") { _ in nil }

        XCTAssertNil(password)
    }
}
