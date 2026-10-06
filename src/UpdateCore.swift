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
    /// Commits on the checked-out HEAD that the update branch's upstream lacks, as of the clone's
    /// last fetch. When the clone is on another branch, these are what the new build leaves out.
    let commitsNotOnUpdateBranch: Int?
    /// The latest upstream commit is already part of the commit this app was built from, as when
    /// the app was built from a branch ahead of master. False when git can't tell, for example
    /// because the clone hasn't fetched that commit yet.
    let buildIncludesLatest: Bool
}

/// Why the app won't install into the clone itself.
enum CloneBlockReason: Equatable {
    /// The clone can't cleanly switch branches and back. The only reason that opens Finder.
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
    /// the upstream commit, and the clone can then switch back.
    case installable
    /// A newer commit exists, but the app can't install it into this clone without risking the
    /// user's work or building the wrong commit.
    case blocked(CloneBlockReason)
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
        return blockReason(clone: clone, branch: branch).map(UpdateStatus.blocked) ?? .installable
    }

    /// The first reason the install could not switch to `branch`, fast-forward it to the latest
    /// commit, and switch back; nil when it can. Being on another branch, or on no branch, is not
    /// a reason: the install returns to whatever was checked out.
    static func blockReason(clone: CloneState, branch: String) -> CloneBlockReason? {
        if clone.hasUncommittedChanges { return .uncommittedChanges }
        if clone.upstreamBranch != branch || clone.upstreamRemoteURL.map(isUpstreamRepoURL) != true {
            return .notTrackingUpstream
        }
        // Unpushed commits on the update branch mean a fast-forward pull can't land on upstream.
        // A count git could not produce (nil) is treated the same, so that clone is never pulled.
        if clone.unpushedCommitCount != 0 { return .unpushedCommits }
        return nil
    }

    /// Why the app left the clone alone, and what to do: one short line each.
    static func blockedMessage(reason: CloneBlockReason, branch: String) -> String {
        switch reason {
        case .uncommittedChanges:
            return "Your clone has uncommitted changes.\nCommit or stash them, then check again."
        case .unpushedCommits:
            return "Your local \(branch) has commits that aren't on GitHub.\n"
                + "Update it yourself, then run ./update.sh."
        case .notTrackingUpstream:
            return "Your local \(branch) is missing or tracks a fork.\n"
                + "Update it yourself, then run ./update.sh."
        }
    }

    /// What Install will do, one short line each. From another branch it also says what the new
    /// app leaves out, since it is built from `branch`.
    static func installMessage(clone: CloneState, branch: String) -> String {
        if clone.branch == branch {
            return "Claude Usage will pull the latest \(branch), rebuild, and restart."
        }
        var lines = [
            "Claude Usage will rebuild from \(branch) and restart.",
            "Your clone switches to \(branch), then back to \(clone.branch ?? "the current commit").",
        ]
        let source = clone.branch.map { "on \($0)" } ?? "not on \(branch)"
        switch clone.commitsNotOnUpdateBranch {
        case 0:
            break
        case 1:
            lines.append("1 commit \(source) won't be in the new app.")
        case .some(let count):
            lines.append("\(count) commits \(source) won't be in the new app.")
        case nil:
            lines.append("Commits \(source) won't be in the new app.")
        }
        return lines.joined(separator: "\n")
    }

    /// The menu row for a status, or nil when there is nothing to offer.
    static func menuTitle(for status: UpdateStatus) -> String? {
        switch status {
        case .upToDate: return nil
        case .installable: return "Update available — click to install"
        case .blocked(.uncommittedChanges): return "Update available (clone has local changes)"
        case .blocked: return "Update available (can't install automatically)"
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
