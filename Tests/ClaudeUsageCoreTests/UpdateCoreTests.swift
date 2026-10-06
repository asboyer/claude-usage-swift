import Foundation
import Testing

@testable import ClaudeUsageCore

struct UpdateCoreTests {
    private let built = String(repeating: "a", count: 40)
    private let latest = String(repeating: "b", count: 40)

    private func clone(
        branch: String? = "master",
        dirty: Bool = false,
        remoteURL: String? = "git@github.com:asboyer/claude-usage-swift.git",
        upstreamBranch: String? = "master",
        unpushed: Int? = 0,
        aheadOfUpdateBranch: Int? = 0,
        includesLatest: Bool = false
    ) -> CloneState {
        CloneState(
            branch: branch,
            hasUncommittedChanges: dirty,
            upstreamRemoteURL: remoteURL,
            upstreamBranch: upstreamBranch,
            unpushedCommitCount: unpushed,
            commitsNotOnUpdateBranch: aheadOfUpdateBranch,
            buildIncludesLatest: includesLatest
        )
    }

    // MARK: - status

    @Test func matchingHashesAreUpToDate() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: built, clone: clone(dirty: true), branch: "master")
        #expect(status == .upToDate)
    }

    @Test func hashComparisonIgnoresCase() {
        let status = UpdateCore.status(
            builtHash: built.uppercased(), latestHash: built, clone: clone(), branch: "master")
        #expect(status == .upToDate)
    }

    @Test func cleanMasterTrackingUpstreamIsInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(), branch: "master")
        #expect(status == .installable)
    }

    @Test func otherBranchWithCleanMasterIsInstallable() {
        // The install switches to master, pulls, builds, and switches back.
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(branch: "feat/x"), branch: "master")
        #expect(status == .installable)
    }

    @Test func otherBranchWithUncommittedChangesIsBlockedByThoseChanges() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(branch: "feat/x", dirty: true), branch: "master")
        #expect(status == .blocked(.uncommittedChanges))
    }

    @Test func detachedHeadIsInstallable() {
        // The install switches back to the checked-out commit afterwards.
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(branch: nil), branch: "master")
        #expect(status == .installable)
    }

    @Test func uncommittedChangesOnTheUpdateBranchAreBlocked() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(dirty: true), branch: "master")
        #expect(status == .blocked(.uncommittedChanges))
    }

    @Test func unpushedCommitsOnLocalMasterAreBlocked() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(unpushed: 2), branch: "master")
        #expect(status == .blocked(.unpushedCommits))
    }

    @Test func uncountableUnpushedCommitsAreBlocked() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(unpushed: nil), branch: "master")
        #expect(status == .blocked(.unpushedCommits))
    }

    @Test func forkUpstreamIsBlocked() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest,
            clone: clone(remoteURL: "git@github.com:someone/claude-usage-swift.git"), branch: "master")
        #expect(status == .blocked(.notTrackingUpstream))
    }

    @Test func missingLocalMasterIsBlocked() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest,
            clone: clone(remoteURL: nil, upstreamBranch: nil, unpushed: nil), branch: "master")
        #expect(status == .blocked(.notTrackingUpstream))
    }

    @Test func masterTrackingAnotherUpstreamBranchIsBlocked() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(upstreamBranch: "dev"), branch: "master")
        #expect(status == .blocked(.notTrackingUpstream))
    }

    @Test func overriddenBranchIsInstallableWhenCloneIsOnIt() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest,
            clone: clone(branch: "feat/x", upstreamBranch: "feat/x"), branch: "feat/x")
        #expect(status == .installable)
    }

    @Test func buildAheadOfLatestIsUpToDate() {
        // A build from a feature branch that already contains master's newest commit.
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest,
            clone: clone(branch: "feat/x", upstreamBranch: "feat/x", includesLatest: true), branch: "master")
        #expect(status == .upToDate)
    }

    @Test func unknownAncestryFallsBackToOfferingTheUpdate() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(includesLatest: false), branch: "master")
        #expect(status == .installable)
    }

    // MARK: - blockReason

    @Test func blockReasonNamesTheFirstProblem() {
        #expect(UpdateCore.blockReason(clone: clone(), branch: "master") == nil)
        #expect(UpdateCore.blockReason(clone: clone(branch: nil), branch: "master") == nil)
        #expect(UpdateCore.blockReason(clone: clone(branch: "feat/x"), branch: "master") == nil)
        #expect(
            UpdateCore.blockReason(clone: clone(branch: "feat/x", dirty: true, unpushed: 3), branch: "master")
                == .uncommittedChanges)
        #expect(UpdateCore.blockReason(clone: clone(unpushed: 3), branch: "master") == .unpushedCommits)
        #expect(
            UpdateCore.blockReason(
                clone: clone(remoteURL: "git@github.com:someone/claude-usage-swift.git", unpushed: 3),
                branch: "master")
                == .notTrackingUpstream)
    }

    // MARK: - blockedMessage

    @Test func uncommittedMessageSaysHowToUnblock() {
        let message = UpdateCore.blockedMessage(reason: .uncommittedChanges, clonePath: "/clone", branch: "master")
        #expect(
            message
                == "Your clone at /clone has uncommitted changes, so the app can't switch to master and back "
                + "without touching them. Commit or stash them, then check for updates again.")
    }

    @Test func unpushedMessageNamesTheUpdateBranch() {
        let message = UpdateCore.blockedMessage(reason: .unpushedCommits, clonePath: "/clone", branch: "master")
        #expect(
            message
                == "The master branch in your clone at /clone has commits that aren't on "
                + "asboyer/claude-usage-swift, so it can't be fast-forwarded. "
                + "Update the clone yourself, then run ./update.sh.")
    }

    @Test func notTrackingMessageMentionsForks() {
        let message = UpdateCore.blockedMessage(
            reason: .notTrackingUpstream, clonePath: "/clone", branch: "master")
        #expect(message.contains("(it may be a fork)"))
        #expect(message.hasSuffix(" Update the clone yourself, then run ./update.sh."))
    }

    // MARK: - installMessage

    @Test func installMessageOnTheUpdateBranchJustPulls() {
        let message = UpdateCore.installMessage(clone: clone(), clonePath: "/clone", branch: "master")
        #expect(message == "Installing pulls master in /clone, rebuilds, and relaunches the app.")
    }

    @Test func installMessageFromABranchAheadOfMasterCountsWhatIsLeftOut() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: "feat/x", aheadOfUpdateBranch: 3), clonePath: "/clone", branch: "master")
        #expect(
            message
                == "Installing switches your clone at /clone to master, pulls, rebuilds, and relaunches the "
                + "app, then switches back to feat/x. 3 commits on feat/x aren't on master. The new app is "
                + "built from master, so it won't include those commits.")
    }

    @Test func installMessageUsesSingularForOneCommit() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: "feat/x", aheadOfUpdateBranch: 1), clonePath: "/clone", branch: "master")
        let expected =
            " 1 commit on feat/x isn't on master. The new app is built from master, so it won't include that commit."
        #expect(message.hasSuffix(expected))
    }

    @Test func installMessageFromABranchWithNothingNewLeavesNothingOut() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: "feat/x", aheadOfUpdateBranch: 0), clonePath: "/clone", branch: "master")
        #expect(message.hasSuffix("then switches back to feat/x."))
    }

    @Test func installMessageWhenTheCountIsUnknownStillWarns() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: "feat/x", aheadOfUpdateBranch: nil), clonePath: "/clone", branch: "master")
        #expect(message.hasSuffix(" so it won't include any commits on feat/x that aren't on master."))
    }

    @Test func installMessageFromADetachedHeadSwitchesBackToTheCommit() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: nil, aheadOfUpdateBranch: 2), clonePath: "/clone", branch: "master")
        #expect(message.contains("then switches back to the commit you have checked out."))
        #expect(message.contains(" 2 commits in what you have checked out aren't on master."))
    }

    // MARK: - menuTitle

    @Test func menuTitlesMatchEachStatus() {
        #expect(UpdateCore.menuTitle(for: .upToDate) == nil)
        #expect(UpdateCore.menuTitle(for: .installable) == "Update available — click to install")
        #expect(
            UpdateCore.menuTitle(for: .blocked(.uncommittedChanges))
                == "Update available (clone has local changes)")
        #expect(
            UpdateCore.menuTitle(for: .blocked(.unpushedCommits))
                == "Update available (can't install automatically)")
        #expect(
            UpdateCore.menuTitle(for: .blocked(.notTrackingUpstream))
                == "Update available (can't install automatically)")
    }

    // MARK: - parseCommitHash

    @Test func parsesBareHashWithTrailingNewline() {
        let hash = "2866a008289cd5ec9effb26b1834b9f22728edf8"
        #expect(UpdateCore.parseCommitHash(hash + "\n") == hash)
    }

    @Test func rejectsErrorBodiesAndShortHashes() {
        #expect(UpdateCore.parseCommitHash(#"{"message":"Not Found"}"#) == nil)
        #expect(UpdateCore.parseCommitHash("2866a00") == nil)
        #expect(UpdateCore.parseCommitHash(String(repeating: "z", count: 40)) == nil)
        #expect(UpdateCore.parseCommitHash("") == nil)
    }

    // MARK: - isUpstreamRepoURL

    @Test func acceptsEveryGitURLFormForTheRepo() {
        let urls = [
            "git@github.com:asboyer/claude-usage-swift.git",
            "git@github.com:asboyer/claude-usage-swift",
            "https://github.com/asboyer/claude-usage-swift.git",
            "https://github.com/asboyer/claude-usage-swift/",
            "https://someone@github.com/asboyer/claude-usage-swift.git",
            "ssh://git@github.com/asboyer/claude-usage-swift.git",
            "HTTPS://GitHub.com/Asboyer/Claude-Usage-Swift",
        ]
        for url in urls {
            #expect(UpdateCore.isUpstreamRepoURL(url), "\(url)")
        }
    }

    @Test func rejectsForksLookalikesAndOtherHosts() {
        let urls = [
            "git@github.com:someone/claude-usage-swift.git",
            "https://github.com/asboyer/claude-usage-swift-fork.git",
            "https://gitlab.com/asboyer/claude-usage-swift.git",
            "https://github.com.evil.example/asboyer/claude-usage-swift.git",
            "/Users/someone/claude-usage-swift",
        ]
        for url in urls {
            #expect(!UpdateCore.isUpstreamRepoURL(url), "\(url)")
        }
    }

    // MARK: - branchName

    @Test func branchNameStripsHeadsPrefix() {
        #expect(UpdateCore.branchName(fromMergeRef: "refs/heads/master\n") == "master")
        #expect(UpdateCore.branchName(fromMergeRef: "refs/heads/feat/x") == "feat/x")
        #expect(UpdateCore.branchName(fromMergeRef: "refs/tags/v1") == nil)
        #expect(UpdateCore.branchName(fromMergeRef: "refs/heads/") == nil)
    }

    // MARK: - latestCommitURL

    @Test func latestCommitURLPointsAtTheRepoBranch() {
        #expect(
            UpdateCore.latestCommitURL(branch: "master")?.absoluteString
                == "https://api.github.com/repos/asboyer/claude-usage-swift/commits/master")
    }
}
