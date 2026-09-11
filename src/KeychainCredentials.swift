import Foundation

/// Result of running `/usr/bin/security`: its exit status and whatever it wrote to stdout.
typealias SecurityRunner = ([String]) -> (status: Int32, output: Data)?

/// Reads a generic password from the login keychain by shelling out to `/usr/bin/security`.
///
/// Every keychain ACL grant is pinned to the requesting binary's designated requirement. An ad-hoc
/// signed app has no stable one, so macOS pins the exact build hash and the grant dies on the next
/// rebuild. `/usr/bin/security` is pinned to an identity instead, so reading through it means one
/// "Always Allow" holds forever. Calling `SecItemCopyMatching` in-process re-prompts on every build.
func keychainPassword(
    service: String,
    account: String? = nil,
    run: SecurityRunner = runSecurity
) -> String? {
    var arguments = ["find-generic-password", "-s", service]
    if let account {
        arguments += ["-a", account]
    }
    arguments.append("-w")

    guard let result = run(arguments), result.status == 0 else { return nil }
    let password = String(data: result.output, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let password, !password.isEmpty else { return nil }
    return password
}

func runSecurity(_ arguments: [String]) -> (status: Int32, output: Data)? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
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
    return (process.terminationStatus, data)
}
