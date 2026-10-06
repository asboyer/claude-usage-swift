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
        unpushed: Int? = 0
    ) -> CloneState {
        CloneState(
            branch: branch,
            hasUncommittedChanges: dirty,
            upstreamRemoteURL: remoteURL,
            upstreamBranch: upstreamBranch,
            unpushedCommitCount: unpushed
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

    @Test func otherBranchIsNotInstallable() {
        let status = UpdateCore.status(
            builtHash: built, latestHash: latest, clone: clone(branch: "feat/x"), branch: "master")
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
