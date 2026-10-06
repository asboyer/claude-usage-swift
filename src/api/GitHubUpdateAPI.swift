import Foundation

// MARK: - Update check (GitHub commits API)

/// Where this build came from, written into Info.plist by build.sh.
/// Nil when the app was not built from a git checkout, which turns the updater off.
struct BuildSource {
    let commitHash: String
    let clonePath: String
    /// Branch whose newest commit counts as an update; `master` unless the build overrode it.
    let updateBranch: String

    static func current(bundle: Bundle = .main) -> BuildSource? {
        guard
            let hash = (bundle.object(forInfoDictionaryKey: "ClaudeUsageCommit") as? String)
                .flatMap(UpdateCore.parseCommitHash),
            let clone = bundle.object(forInfoDictionaryKey: "ClaudeUsageClonePath") as? String,
            !clone.isEmpty
        else { return nil }
        let branch = bundle.object(forInfoDictionaryKey: "ClaudeUsageUpdateBranch") as? String
        return BuildSource(
            commitHash: hash,
            clonePath: clone,
            updateBranch: (branch?.isEmpty == false) ? branch! : UpdateCore.defaultBranch
        )
    }
}

/// An ephemeral session so the check carries no cookies or cached credentials.
private let updateCheckSession = URLSession(configuration: .ephemeral)

/// Fetches the newest commit hash on `branch`. Sends no login and nothing about the user.
func fetchLatestCommitHash(branch: String, completion: @escaping (String?) -> Void) {
    guard let url = UpdateCore.latestCommitURL(branch: branch) else {
        completion(nil)
        return
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 20
    request.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")
    // GitHub requires a User-Agent; this replaces the default one that names the OS version.
    request.setValue("claude-usage-swift", forHTTPHeaderField: "User-Agent")

    updateCheckSession.dataTask(with: request) { data, response, _ in
        guard
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let data, let body = String(data: data, encoding: .utf8)
        else {
            completion(nil)
            return
        }
        completion(UpdateCore.parseCommitHash(body))
    }.resume()
}

// MARK: - Clone inspection (local git only)

/// Runs `git -C <clone> <args>` and returns trimmed stdout, or nil if git failed.
private func runGit(_ args: [String], in clone: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", clone] + args
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Reads the clone's branch, uncommitted changes, and upstream. Blocks; call off the main thread.
/// Nil when the clone is gone or is not a git checkout.
func inspectClone(at clone: String) -> CloneState? {
    guard runGit(["rev-parse", "--is-inside-work-tree"], in: clone) == "true" else { return nil }
    let branch = runGit(["symbolic-ref", "--short", "-q", "HEAD"], in: clone)
    let status = runGit(["status", "--porcelain", "--untracked-files=no"], in: clone)

    var remoteURL: String?
    var upstreamBranch: String?
    if let branch {
        if let remote = runGit(["config", "--get", "branch.\(branch).remote"], in: clone) {
            remoteURL = runGit(["remote", "get-url", remote], in: clone)
        }
        upstreamBranch = runGit(["config", "--get", "branch.\(branch).merge"], in: clone)
            .flatMap(UpdateCore.branchName(fromMergeRef:))
    }
    let unpushed = runGit(["rev-list", "--count", "@{upstream}..HEAD"], in: clone).flatMap { Int($0) }

    return CloneState(
        branch: branch,
        // A failed `git status` counts as changes, so an unreadable clone is never pulled.
        hasUncommittedChanges: status.map { !$0.isEmpty } ?? true,
        upstreamRemoteURL: remoteURL,
        upstreamBranch: upstreamBranch,
        unpushedCommitCount: unpushed
    )
}

// MARK: - Installing

let updateLogURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/ClaudeUsage/update.log")

/// Starts `git pull --ff-only && ./update.sh` in the clone as its own process, so it outlives this
/// app when update.sh quits it. Output goes to `updateLogURL`. `onFailure` runs on the main queue
/// if the process exits non-zero; on success update.sh has already quit and replaced this app.
func startUpdateInstall(source: BuildSource, onFailure: @escaping () -> Void) -> Bool {
    let fileManager = FileManager.default
    try? fileManager.createDirectory(
        at: updateLogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let header = "Update started \(ISO8601DateFormatter().string(from: Date())) in \(source.clonePath)\n"
    guard fileManager.createFile(atPath: updateLogURL.path, contents: Data(header.utf8)),
        let log = try? FileHandle(forWritingTo: updateLogURL)
    else { return false }
    log.seekToEndOfFile()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    // The clone path is passed as $1, never spliced into the script text.
    process.arguments = [
        "-c", #"cd "$1" && git pull --ff-only && ./update.sh"#, "claude-usage-update", source.clonePath,
    ]
    var environment = ProcessInfo.processInfo.environment
    // The rebuilt app keeps checking the branch this one checks.
    environment["CLAUDEUSAGE_UPDATE_BRANCH"] = source.updateBranch
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = log
    process.standardError = log
    process.terminationHandler = { finished in
        try? log.close()
        if finished.terminationStatus != 0 {
            DispatchQueue.main.async(execute: onFailure)
        }
    }
    do {
        try process.run()
        return true
    } catch {
        try? log.close()
        return false
    }
}
