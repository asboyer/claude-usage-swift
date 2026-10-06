import Foundation

// MARK: - Clone State

/// What local git reports about the clone this app was built from.
/// Gathered with local git commands only; nothing here touches the network.
struct CloneState: Equatable {
    /// Checked-out branch, or nil on a detached HEAD.
    let branch: String?
    /// Modified or staged tracked files. Untracked files do not block a checkout or a pull.
    let hasUncommittedChanges: Bool
    /// Remote and branch the local update branch (normally `master`) pulls from, or nil when
    /// that branch has no upstream or does not exist locally. Read for the update branch, not the
    /// checked-out one, because the install switches to the update branch before pulling.
    let upstreamRemoteURL: String?
    let upstreamBranch: String?
    /// Commits on the local update branch that its upstream lacks, or nil when that could not be
    /// counted.
    let unpushedCommitCount: Int?
    /// The latest upstream commit is already part of the commit this app was built from, as when
    /// the app was built from a branch ahead of master. False when git can't tell, for example
    /// because the clone hasn't fetched that commit yet.
    let buildIncludesLatest: Bool
}

/// Why the app won't pull into the clone itself.
enum CloneBlockReason: Equatable {
    /// Nothing to switch back to after building another branch.
    case detachedHead
    case uncommittedChanges
    case unpushedCommits
    /// Pulls from a fork, another branch, or nothing.
    case notTrackingUpstream
}

// MARK: - Update Status

/// What the menu should offer once the latest upstream commit is known.
enum UpdateStatus: Equatable {
    case upToDate
    /// Switching the clone to the update branch, `git pull --ff-only`, and `./update.sh` will build
    /// the upstream commit.
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
    /// A different hash is not necessarily a newer one: a build ahead of `branch` is up to date.
    static func status(builtHash: String, latestHash: String, clone: CloneState, branch: String)
        -> UpdateStatus
    {
        if builtHash.lowercased() == latestHash.lowercased() || clone.buildIncludesLatest {
            return .upToDate
        }
        return blockReason(clone: clone, branch: branch) == nil ? .installable : .cloneHasLocalChanges
    }

    /// The first reason the install could not switch to `branch`, fast-forward it to the latest
    /// commit, and switch back; nil when it can. Being on another branch is not a reason.
    static func blockReason(clone: CloneState, branch: String) -> CloneBlockReason? {
        if clone.branch == nil { return .detachedHead }
        if clone.hasUncommittedChanges { return .uncommittedChanges }
        if clone.upstreamBranch != branch || clone.upstreamRemoteURL.map(isUpstreamRepoURL) != true {
            return .notTrackingUpstream
        }
        // Unpushed commits on the update branch mean a fast-forward pull can't land on upstream.
        // A count git could not produce (nil) is treated the same, so that clone is never pulled.
        if clone.unpushedCommitCount != 0 { return .unpushedCommits }
        return nil
    }

    /// Says in plain words why the app left the clone alone, and what to do instead.
    static func blockedMessage(reason: CloneBlockReason, clonePath: String, branch: String) -> String {
        let repo = "\(repoOwner)/\(repoName)"
        let problem: String
        switch reason {
        case .detachedHead:
            problem =
                "Your clone at \(clonePath) isn't on a branch, so the app couldn't switch back "
                + "after updating."
        case .uncommittedChanges:
            problem =
                "Your clone at \(clonePath) has uncommitted changes, so the app won't switch "
                + "branches or pull."
        case .unpushedCommits:
            problem =
                "The \(branch) branch in your clone at \(clonePath) has commits that aren't on "
                + "\(repo), so it can't be fast-forwarded."
        case .notTrackingUpstream:
            problem =
                "The \(branch) branch in your clone at \(clonePath) is missing or doesn't pull from "
                + "\(repo) (it may be a fork), so pulling wouldn't get this update."
        }
        return problem + " Update the clone yourself, then run ./update.sh."
    }

    /// Says what Install will do to the clone. When the clone is on another branch, the install
    /// builds `branch` and switches back, so the new app lacks that branch's changes.
    static func installMessage(clone: CloneState, clonePath: String, branch: String) -> String {
        guard let current = clone.branch, current != branch else {
            return "Installing pulls \(branch) in \(clonePath), rebuilds, and relaunches the app."
        }
        return "Installing switches your clone at \(clonePath) from \(current) to \(branch), pulls, "
            + "rebuilds, and relaunches the app, then switches back to \(current). "
            + "The new app is built from \(branch), so it won't include changes that are only on \(current)."
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
