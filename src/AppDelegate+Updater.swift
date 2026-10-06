import Cocoa

// MARK: - In-app updater

/// What the update row in the main menu shows.
enum UpdateMenuState: Equatable {
    case hidden
    case available(UpdateStatus)
    case installing
    case failed
}

extension AppDelegate {
    static let updateCheckInterval: TimeInterval = 6 * 60 * 60

    /// Checks at launch and every 6 hours, on its own timer so the usage refresh interval
    /// does not change how often GitHub is asked.
    func startUpdateChecks() {
        guard buildSource != nil else { return }
        checkForUpdates(userInitiated: false)
        updateCheckTimer?.invalidate()
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: Self.updateCheckInterval, repeats: true) {
            [weak self] _ in
            self?.checkForUpdates(userInitiated: false)
        }
        updateCheckTimer?.tolerance = 600
    }

    @objc func checkForUpdatesFromMenu() {
        checkForUpdates(userInitiated: true)
    }

    func checkForUpdates(userInitiated: Bool) {
        guard let source = buildSource, updateMenuState != .installing else { return }
        fetchLatestCommitHash(branch: source.updateBranch) { [weak self] latest in
            // Runs on URLSession's queue, so the git calls stay off the main thread.
            let clone = latest.flatMap {
                inspectClone(
                    at: source.clonePath, updateBranch: source.updateBranch, builtHash: source.commitHash,
                    latestHash: $0)
            }
            DispatchQueue.main.async {
                self?.applyUpdateCheck(latest: latest, clone: clone, userInitiated: userInitiated)
            }
        }
    }

    private func applyUpdateCheck(latest: String?, clone: CloneState?, userInitiated: Bool) {
        guard let source = buildSource, updateMenuState != .installing else { return }
        guard let latest else {
            // Keep whatever the menu showed; a failed check says nothing new.
            if userInitiated {
                showUpdateAlert(
                    title: "Couldn't check for updates",
                    message: "GitHub could not be reached. Try again later.")
            }
            return
        }
        latestUpdateHash = latest
        guard let clone else {
            updateMenuState = .hidden
            refreshUpdateItem()
            if userInitiated {
                showUpdateAlert(
                    title: "Can't find the clone",
                    message: "This app was built from \(source.clonePath), which is no longer a git clone.")
            }
            return
        }

        let status = UpdateCore.status(
            builtHash: source.commitHash, latestHash: latest, clone: clone, branch: source.updateBranch)
        // A failed install stays on screen until the user checks again by hand.
        if updateMenuState != .failed || userInitiated {
            updateMenuState = status == .upToDate ? .hidden : .available(status)
            refreshUpdateItem()
        }
        if userInitiated {
            presentCheckResult(status, clone: clone, source: source)
        }
    }

    private func presentCheckResult(_ status: UpdateStatus, clone: CloneState, source: BuildSource) {
        switch status {
        case .upToDate:
            showUpdateAlert(
                title: "Claude Usage is up to date",
                message: "Built from \(source.commitHash.prefix(7)), which includes the latest commit on "
                    + "\(source.updateBranch).")
        case .installable:
            let install = showUpdateAlert(
                title: "An update is available",
                message: UpdateCore.installMessage(
                    clone: clone, clonePath: source.clonePath, branch: source.updateBranch),
                buttons: ["Install", "Later"])
            if install == .alertFirstButtonReturn { installUpdate(confirmed: true) }
        case .cloneHasLocalChanges:
            let reveal = showUpdateAlert(
                title: "An update is available",
                message: UpdateCore.blockedMessage(
                    reason: UpdateCore.blockReason(clone: clone, branch: source.updateBranch)
                        ?? .notTrackingUpstream,
                    clonePath: source.clonePath, branch: source.updateBranch),
                buttons: ["Show in Finder", "OK"])
            if reveal == .alertFirstButtonReturn { revealClone() }
        }
    }

    @objc func updateItemClicked() {
        switch updateMenuState {
        case .available:
            // Installs, or opens the clone in Finder if it can't be pulled.
            installUpdate()
        case .failed:
            NSWorkspace.shared.open(updateLogURL)
        case .hidden, .installing:
            break
        }
    }

    /// Re-reads the clone first: the last check may be hours old. `confirmed` means the user already
    /// saw what Install does to the clone.
    func installUpdate(confirmed: Bool = false) {
        guard let source = buildSource, let latest = latestUpdateHash else { return }
        guard
            let clone = inspectClone(
                at: source.clonePath, updateBranch: source.updateBranch, builtHash: source.commitHash,
                latestHash: latest)
        else {
            updateMenuState = .hidden
            refreshUpdateItem()
            return
        }
        let status = UpdateCore.status(
            builtHash: source.commitHash, latestHash: latest, clone: clone, branch: source.updateBranch)
        switch status {
        case .upToDate:
            updateMenuState = .hidden
        case .cloneHasLocalChanges:
            updateMenuState = .available(.cloneHasLocalChanges)
            revealClone()
        case .installable:
            // Building another branch leaves that branch's changes out of the app, so say so first.
            if !confirmed && clone.branch != source.updateBranch {
                let install = showUpdateAlert(
                    title: "Install the update?",
                    message: UpdateCore.installMessage(
                        clone: clone, clonePath: source.clonePath, branch: source.updateBranch),
                    buttons: ["Install", "Cancel"])
                guard install == .alertFirstButtonReturn else { return }
            }
            updateMenuState = .installing
            let started = startUpdateInstall(source: source) { [weak self] in
                self?.updateMenuState = .failed
                self?.refreshUpdateItem()
            }
            if !started { updateMenuState = .failed }
        }
        refreshUpdateItem()
    }

    private func revealClone() {
        guard let source = buildSource else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: source.clonePath, isDirectory: true))
    }

    func refreshUpdateItem() {
        guard let updateItem else { return }
        switch updateMenuState {
        case .hidden:
            updateItem.isHidden = true
        case .available(let status):
            updateItem.title = UpdateCore.menuTitle(for: status) ?? ""
            updateItem.isHidden = UpdateCore.menuTitle(for: status) == nil
            updateItem.isEnabled = true
            updateItem.action = #selector(updateItemClicked)
        case .installing:
            updateItem.title = "Installing update…"
            updateItem.isHidden = false
            updateItem.isEnabled = false
            updateItem.action = nil
        case .failed:
            updateItem.title = "Update failed — see log"
            updateItem.isHidden = false
            updateItem.isEnabled = true
            updateItem.action = #selector(updateItemClicked)
        }
    }

    @discardableResult
    private func showUpdateAlert(title: String, message: String, buttons: [String] = ["OK"])
        -> NSApplication.ModalResponse
    {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(.accessory) }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for button in buttons { alert.addButton(withTitle: button) }
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            alert.icon = NSImage(contentsOfFile: iconPath)
        }
        return alert.runModal()
    }
}
