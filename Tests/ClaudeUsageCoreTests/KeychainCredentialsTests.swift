import Foundation
import Testing

@testable import ClaudeUsageCore

struct KeychainCredentialsTests {
    @Test func returnsTrimmedPasswordOnSuccess() {
        var captured: [String] = []
        let password = keychainPassword(service: "Claude Code-credentials") { arguments in
            captured = arguments
            return (0, Data("{\"claudeAiOauth\":{}}\n".utf8))
        }

        #expect(password == "{\"claudeAiOauth\":{}}")
        #expect(captured == ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
    }

    @Test func passesAccountWhenGiven() {
        var captured: [String] = []
        _ = keychainPassword(service: "cursor-access-token", account: "cursor-user") { arguments in
            captured = arguments
            return (0, Data("token".utf8))
        }

        #expect(captured == ["find-generic-password", "-s", "cursor-access-token", "-a", "cursor-user", "-w"])
    }

    @Test func returnsNilWhenItemNotFound() {
        // `security` exits 44 (errSecItemNotFound) and writes nothing.
        let password = keychainPassword(service: "no-such-service") { _ in (44, Data()) }

        #expect(password == nil)
    }

    @Test func returnsNilWhenPasswordIsBlank() {
        let password = keychainPassword(service: "Claude Safe Storage") { _ in (0, Data("\n".utf8)) }

        #expect(password == nil)
    }

    @Test func returnsNilWhenSecurityCannotLaunch() {
        let password = keychainPassword(service: "Claude Safe Storage") { _ in nil }

        #expect(password == nil)
    }
}
