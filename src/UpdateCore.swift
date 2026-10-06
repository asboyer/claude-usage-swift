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

    /// Says in plain words why the app left the clone alone, and what to do instead.
    static func blockedMessage(reason: CloneBlockReason, clonePath: String, branch: String) -> String {
        let repo = "\(repoOwner)/\(repoName)"
        let problem: String
        switch reason {
        case .uncommittedChanges:
            // The one case the user can fix in place, after which the app installs by itself.
            return "Your clone at \(clonePath) has uncommitted changes, so the app can't switch to "
                + "\(branch) and back without touching them. Commit or stash them, then check for "
                + "updates again."
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
    /// builds `branch` and switches back, so the new app lacks that branch's own commits.
    static func installMessage(clone: CloneState, clonePath: String, branch: String) -> String {
        if clone.branch == branch {
            return "Installing pulls \(branch) in \(clonePath), rebuilds, and relaunches the app."
        }
        let current = clone.branch ?? "the commit you have checked out"
        let place = clone.branch.map { "on \($0)" } ?? "in what you have checked out"
        let steps =
            "Installing switches your clone at \(clonePath) to \(branch), pulls, rebuilds, and "
            + "relaunches the app, then switches back to \(current)."
        switch clone.commitsNotOnUpdateBranch {
        case 0:
            return steps
        case 1:
            return steps + " 1 commit \(place) isn't on \(branch). The new app is built from \(branch), "
                + "so it won't include that commit."
        case .some(let count):
            return steps + " \(count) commits \(place) aren't on \(branch). The new app is built from "
                + "\(branch), so it won't include those commits."
        case nil:
            return steps + " The new app is built from \(branch), so it won't include any commits "
                + "\(place) that aren't on \(branch)."
        }
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
