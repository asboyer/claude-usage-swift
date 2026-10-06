import Foundation

// MARK: - Clone State

/// What local git reports about the clone this app was built from.
/// Gathered with local git commands only; nothing here touches the network.
struct CloneState: Equatable {
    /// Checked-out branch, or nil on a detached HEAD.
    let branch: String?
    /// Modified or staged tracked files. Untracked files do not block a fast-forward pull.
    let hasUncommittedChanges: Bool
    /// Remote and branch the checked-out branch pulls from, or nil when it has no upstream.
    let upstreamRemoteURL: String?
    let upstreamBranch: String?
    /// Commits on HEAD that the upstream branch lacks, or nil when that could not be counted.
    let unpushedCommitCount: Int?
}

// MARK: - Update Status

/// What the menu should offer once the latest upstream commit is known.
enum UpdateStatus: Equatable {
    case upToDate
    /// `git pull --ff-only && ./update.sh` in the clone will land on the upstream commit.
    case installable
    /// A newer commit exists, but pulling in this clone could fail or leave the build unchanged,
    /// so the app only points at the clone.
    case cloneHasLocalChanges
}

enum UpdateCore {
    static let repoOwner = "asboyer"
    static let repoName = "claude-usage-swift"
    static let defaultBranch = "master"

    /// `GET` this with `Accept: application/vnd.github.sha` and the body is the bare commit hash.
    static func latestCommitURL(branch: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/commits/\(branch)")
    }

    /// Accepts only a full 40-character hex hash, so an error page is never mistaken for one.
    static func parseCommitHash(_ body: String) -> String? {
        let hash = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hash.count == 40, hash.allSatisfy({ $0.isHexDigit }) else { return nil }
        return hash
    }

    /// True when a remote URL points at this repo on GitHub, in any of git's URL forms.
    /// A fork's URL is false: the check reads this repo, so pulling a fork would not catch up.
    static func isUpstreamRepoURL(_ url: String) -> Bool {
        var rest = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = rest.range(of: "://") { rest = String(rest[scheme.upperBound...]) }
        // Drop a user such as `git@` or `name@`, but only from the host part.
        if let at = rest.firstIndex(of: "@"), at < (rest.firstIndex(of: "/") ?? rest.endIndex) {
            rest = String(rest[rest.index(after: at)...])
        }
        // `github.com/owner/repo` for URLs, `github.com:owner/repo` for scp-style SSH.
        guard rest.hasPrefix("github.com/") || rest.hasPrefix("github.com:") else { return false }
        var path = String(rest.dropFirst("github.com/".count))
        if path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        return path == "\(repoOwner)/\(repoName)"
    }

    /// Decides what to offer, given the commit this app was built from and the latest upstream one.
    static func status(builtHash: String, latestHash: String, clone: CloneState, branch: String)
        -> UpdateStatus
    {
        if builtHash.lowercased() == latestHash.lowercased() { return .upToDate }
        let pullsUpstream =
            clone.branch == branch
            && !clone.hasUncommittedChanges
            && clone.upstreamBranch == branch
            && clone.upstreamRemoteURL.map(isUpstreamRepoURL) == true
            // Unpushed commits mean the pull is a no-op and the rebuild reproduces this build.
            && clone.unpushedCommitCount == 0
        return pullsUpstream ? .installable : .cloneHasLocalChanges
    }

    /// The menu row for a status, or nil when there is nothing to offer.
    static func menuTitle(for status: UpdateStatus) -> String? {
        switch status {
        case .upToDate: return nil
        case .installable: return "Update available — click to install"
        case .cloneHasLocalChanges: return "Update available (clone has local changes)"
        }
    }

    /// The branch an upstream ref such as `refs/heads/master` names.
    static func branchName(fromMergeRef ref: String) -> String? {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "refs/heads/"
        guard trimmed.hasPrefix(prefix), trimmed.count > prefix.count else { return nil }
        return String(trimmed.dropFirst(prefix.count))
    }
}
