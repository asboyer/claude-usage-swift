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
        includesLatest: Bool = false
    ) -> CloneState {
        CloneState(
            branch: branch,
            hasUncommittedChanges: dirty,
            upstreamRemoteURL: remoteURL,
            upstreamBranch: upstreamBranch,
            unpushedCommitCount: unpushed,
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

    @Test func otherBranchWithUncommittedChangesIsNotInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(branch: "feat/x", dirty: true), branch: "master")
        #expect(status == .cloneHasLocalChanges)
    }

    @Test func detachedHeadIsNotInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(branch: nil), branch: "master")
        #expect(status == .cloneHasLocalChanges)
    }

    @Test func uncommittedChangesAreNotInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(dirty: true), branch: "master")
        #expect(status == .cloneHasLocalChanges)
    }

    @Test func unpushedCommitsAreNotInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(unpushed: 2), branch: "master")
        #expect(status == .cloneHasLocalChanges)
    }

    @Test func uncountableUnpushedCommitsAreNotInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(unpushed: nil), branch: "master")
        #expect(status == .cloneHasLocalChanges)
    }

    @Test func forkUpstreamIsNotInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest,
            clone: clone(remoteURL: "git@github.com:someone/claude-usage-swift.git"), branch: "master")
        #expect(status == .cloneHasLocalChanges)
    }

    @Test func missingUpstreamIsNotInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest,
            clone: clone(remoteURL: nil, upstreamBranch: nil, unpushed: nil), branch: "master")
        #expect(status == .cloneHasLocalChanges)
    }

    @Test func masterTrackingAnotherUpstreamBranchIsNotInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(upstreamBranch: "dev"), branch: "master")
        #expect(status == .cloneHasLocalChanges)
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
        #expect(UpdateCore.blockReason(clone: clone(branch: nil), branch: "master") == .detachedHead)
        #expect(UpdateCore.blockReason(clone: clone(branch: "feat/x"), branch: "master") == nil)
        #expect(
            UpdateCore.blockReason(clone: clone(branch: "feat/x", dirty: true), branch: "master")
                == .uncommittedChanges)
        #expect(UpdateCore.blockReason(clone: clone(dirty: true), branch: "master") == .uncommittedChanges)
        #expect(UpdateCore.blockReason(clone: clone(unpushed: 3), branch: "master") == .unpushedCommits)
        #expect(UpdateCore.blockReason(clone: clone(unpushed: nil), branch: "master") == .unpushedCommits)
        #expect(
            UpdateCore.blockReason(
                clone: clone(remoteURL: "git@github.com:someone/claude-usage-swift.git"), branch: "master")
                == .notTrackingUpstream)
        #expect(
            UpdateCore.blockReason(
                clone: clone(remoteURL: nil, upstreamBranch: nil, unpushed: nil), branch: "master")
                == .notTrackingUpstream)
    }

    // MARK: - blockedMessage

    @Test func unpushedMessageNamesTheUpdateBranch() {
        let message = UpdateCore.blockedMessage(reason: .unpushedCommits, clonePath: "/clone", branch: "master")
        #expect(
            message
                == "The master branch in your clone at /clone has commits that aren't on "
                + "asboyer/claude-usage-swift, so it can't be fast-forwarded. "
                + "Update the clone yourself, then run ./update.sh.")
    }

    @Test func everyBlockedMessageEndsWithWhatToDo() {
        let reasons: [CloneBlockReason] = [
            .detachedHead, .uncommittedChanges, .unpushedCommits, .notTrackingUpstream,
        ]
        for reason in reasons {
            let message = UpdateCore.blockedMessage(reason: reason, clonePath: "/clone", branch: "master")
            #expect(message.contains(" clone at /clone "))
            #expect(message.hasSuffix(" Update the clone yourself, then run ./update.sh."))
        }
    }

    // MARK: - installMessage

    @Test func installMessageOnTheUpdateBranchJustPulls() {
        let message = UpdateCore.installMessage(clone: clone(), clonePath: "/clone", branch: "master")
        #expect(message == "Installing pulls master in /clone, rebuilds, and relaunches the app.")
    }

    @Test func installMessageFromAnotherBranchSaysItSwitchesBackAndWhatIsLeftOut() {
        let message = UpdateCore.installMessage(
            clone: clone(branch: "feat/x"), clonePath: "/clone", branch: "master")
        #expect(
            message
                == "Installing switches your clone at /clone from feat/x to master, pulls, rebuilds, "
                + "and relaunches the app, then switches back to feat/x. "
                + "The new app is built from master, so it won't include changes that are only on feat/x.")
    }

    // MARK: - menuTitle

    @Test func menuTitlesMatchEachStatus() {
        #expect(UpdateCore.menuTitle(for: .upToDate) == nil)
        #expect(UpdateCore.menuTitle(for: .installable) == "Update available — click to install")
        #expect(
            UpdateCore.menuTitle(for: .cloneHasLocalChanges)
                == "Update available (clone has local changes)")
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
