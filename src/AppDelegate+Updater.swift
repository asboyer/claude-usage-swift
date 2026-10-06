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
            let clone = latest.flatMap { _ in inspectClone(at: source.clonePath) }
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
            presentCheckResult(status, source: source)
        }
    }

    private func presentCheckResult(_ status: UpdateStatus, source: BuildSource) {
        switch status {
        case .upToDate:
            showUpdateAlert(
                title: "Claude Usage is up to date",
                message: "Built from \(source.commitHash.prefix(7)), the latest commit on \(source.updateBranch).")
        case .installable:
            let install = showUpdateAlert(
                title: "An update is available",
                message: "Installing pulls \(source.updateBranch) in \(source.clonePath), rebuilds, "
                    + "and relaunches the app.",
                buttons: ["Install", "Later"])
            if install == .alertFirstButtonReturn { installUpdate() }
        case .cloneHasLocalChanges:
            let reveal = showUpdateAlert(
                title: "An update is available",
                message: cloneBlockedMessage(source: source),
                buttons: ["Show in Finder", "OK"])
            if reveal == .alertFirstButtonReturn { revealClone() }
        }
    }

    private func cloneBlockedMessage(source: BuildSource) -> String {
        "The clone at \(source.clonePath) isn't a clean \(source.updateBranch) that tracks "
            + "\(UpdateCore.repoOwner)/\(UpdateCore.repoName), so the app won't pull into it. "
            + "Update it yourself, then run ./update.sh."
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

    /// Re-reads the clone first: the last check may be hours old.
    func installUpdate() {
        guard let source = buildSource, let latest = latestUpdateHash else { return }
        guard let clone = inspectClone(at: source.clonePath) else {
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
