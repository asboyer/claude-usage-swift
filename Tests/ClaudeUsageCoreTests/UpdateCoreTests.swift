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

    @Test func blockedMessagesAreTwoShortLines() {
        #expect(
            UpdateCore.blockedMessage(reason: .uncommittedChanges, branch: "master")
                == "Your clone has uncommitted changes.\nCommit or stash them, then check again.")
        #expect(
            UpdateCore.blockedMessage(reason: .unpushedCommits, branch: "master")
                == "Your local master has commits that aren't on GitHub.\nUpdate it yourself, then run ./update.sh.")
        #expect(
            UpdateCore.blockedMessage(reason: .notTrackingUpstream, branch: "master")
                == "Your local master is missing or tracks a fork.\nUpdate it yourself, then run ./update.sh.")
    }

    // MARK: - installMessage

    @Test func installMessageOnTheUpdateBranchIsOneLine() {
        let message = UpdateCore.installMessage(clone: clone(), branch: "master")
        #expect(message == "Claude Usage will pull the latest master, rebuild, and restart.")
    }

    @Test func installMessageFromABranchAheadOfMasterSaysWhatIsLeftOut() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: "feat/x", aheadOfUpdateBranch: 3), branch: "master")
        #expect(
            message
                == """
                Claude Usage will rebuild from master and restart.
                Your clone switches to master, then back to feat/x.
                3 commits on feat/x won't be in the new app.
                """)
    }

    @Test func installMessageUsesSingularForOneCommit() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: "feat/x", aheadOfUpdateBranch: 1), branch: "master")
        #expect(message.hasSuffix("\n1 commit on feat/x won't be in the new app."))
    }

    @Test func installMessageFromABranchWithNothingNewIsTwoLines() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: "feat/x", aheadOfUpdateBranch: 0), branch: "master")
        #expect(message.hasSuffix("then back to feat/x."))
    }

    @Test func installMessageWhenTheCountIsUnknownStillWarns() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: "feat/x", aheadOfUpdateBranch: nil), branch: "master")
        #expect(message.hasSuffix("\nCommits on feat/x won't be in the new app."))
    }

    @Test func installMessageFromADetachedHeadSwitchesBackToTheCommit() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: nil, aheadOfUpdateBranch: 2), branch: "master")
        #expect(message.contains("then back to the current commit."))
        #expect(message.hasSuffix("\n2 commits not on master won't be in the new app."))
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
