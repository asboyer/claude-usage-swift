import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import WebKit

extension AppDelegate {
    func buildMenu() {
        menu.removeAllItems()

        // Pinned usage items with rate sub-items, grouped by provider
        let showsProviderSections = codexSectionVisible || cursorSectionVisible
        addUsageSection(provider: .claude, keys: claudeCategoryKeys, showsHeader: showsProviderSections)
        if codexSectionVisible {
            addUsageSection(provider: .codex, keys: codexCategoryKeys, showsHeader: true)
        }
        if cursorSectionVisible {
            addUsageSection(provider: .cursor, keys: cursorCategoryKeys, showsHeader: true)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(rateLimitItem)
        menu.addItem(updatedItem)

        let graphItem = NSMenuItem(title: "Usage Graph", action: #selector(showUsageGraph), keyEquivalent: "g")
        graphItem.target = self
        graphItem.keyEquivalentModifierMask = []
        menu.addItem(graphItem)

        let copyItem = NSMenuItem(title: "Copy Usage", action: #selector(copyUsage), keyEquivalent: "c")
        copyItem.target = self
        copyItem.keyEquivalentModifierMask = []
        menu.addItem(copyItem)

        let closeItem = NSMenuItem(title: "Close", action: #selector(closeMenu), keyEquivalent: "x")
        closeItem.target = self
        closeItem.keyEquivalentModifierMask = []
        menu.addItem(closeItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.keyEquivalentModifierMask = []
        menu.addItem(refreshItem)
        menu.addItem(NSMenuItem.separator())

        // Settings submenu — contains Refresh Interval, Notifications, More
        let settingsMenu = NSMenu()

        // Refresh Interval submenu
        let intervalMenu = NSMenu()
        interval1mItem = NSMenuItem(title: "Every 1 minute", action: #selector(setInterval1m), keyEquivalent: "")
        interval5mItem = NSMenuItem(title: "Every 5 minutes", action: #selector(setInterval5m), keyEquivalent: "")
        interval30mItem = NSMenuItem(title: "Every 30 minutes", action: #selector(setInterval30m), keyEquivalent: "")
        interval1hItem = NSMenuItem(title: "Every hour", action: #selector(setInterval1h), keyEquivalent: "")
        interval1mItem.target = self
        interval5mItem.target = self
        interval30mItem.target = self
        interval1hItem.target = self
        intervalMenu.addItem(interval1mItem)
        intervalMenu.addItem(interval5mItem)
        intervalMenu.addItem(interval30mItem)
        intervalMenu.addItem(interval1hItem)
        let intervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu
        settingsMenu.addItem(intervalItem)

        colorsItem = NSMenuItem(title: "Colors", action: #selector(toggleColors), keyEquivalent: "")
        colorsItem.target = self
        colorsItem.state = colorsEnabled ? .on : .off
        settingsMenu.addItem(colorsItem)

        rateInsightItem = NSMenuItem(title: "Rate Insight", action: #selector(toggleRateInsight), keyEquivalent: "")
        rateInsightItem.target = self
        rateInsightItem.state = rateInsightEnabled ? .on : .off
        settingsMenu.addItem(rateInsightItem)

        alwaysShowExtraUsageItem = NSMenuItem(
            title: "Always Show Extra Usage",
            action: #selector(toggleAlwaysShowExtraUsage),
            keyEquivalent: ""
        )
        alwaysShowExtraUsageItem.target = self
        alwaysShowExtraUsageItem.state = alwaysShowExtraUsageEnabled ? .on : .off
        settingsMenu.addItem(alwaysShowExtraUsageItem)

        openAtLoginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin), keyEquivalent: "")
        openAtLoginItem.target = self
        openAtLoginItem.state = openAtLoginEnabled ? .on : .off
        settingsMenu.addItem(openAtLoginItem)

        // Usage Source submenu
        let usageSourceMenu = NSMenu()
        usageSourceCookiesItem = NSMenuItem(title: "Use Desktop Cookies (recommended)", action: #selector(selectUsageSourceCookies), keyEquivalent: "")
        usageSourceCookiesItem.target = self
        usageSourceMenu.addItem(usageSourceCookiesItem)
        usageSourceOAuthItem = NSMenuItem(title: "Use OAuth API", action: #selector(selectUsageSourceOAuth), keyEquivalent: "")
        usageSourceOAuthItem.target = self
        usageSourceMenu.addItem(usageSourceOAuthItem)
        let usageSourceItem = NSMenuItem(title: "Usage Source", action: nil, keyEquivalent: "")
        usageSourceItem.submenu = usageSourceMenu
        settingsMenu.addItem(usageSourceItem)

        codexTrackingItem = NSMenuItem(
            title: "Track Codex Usage",
            action: #selector(toggleCodexTracking),
            keyEquivalent: ""
        )
        codexTrackingItem.target = self
        codexTrackingItem.state = codexTrackingEnabled ? .on : .off
        settingsMenu.addItem(codexTrackingItem)

        cursorTrackingItem = NSMenuItem(
            title: "Track Cursor Usage",
            action: #selector(toggleCursorTracking),
            keyEquivalent: ""
        )
        cursorTrackingItem.target = self
        cursorTrackingItem.state = cursorTrackingEnabled ? .on : .off
        settingsMenu.addItem(cursorTrackingItem)

        // Keyboard Shortcut submenu
        let hotkeyMenu = NSMenu()
        hotkeyCurrentItem = NSMenuItem(title: "Current: \(hotkeyDisplayString())", action: nil, keyEquivalent: "")
        hotkeyCurrentItem.isEnabled = false
        hotkeyMenu.addItem(hotkeyCurrentItem)
        hotkeyMenu.addItem(NSMenuItem.separator())
        hotkeyRecordItem = NSMenuItem(title: "Record New Shortcut...", action: #selector(recordHotkey), keyEquivalent: "")
        hotkeyRecordItem.target = self
        hotkeyMenu.addItem(hotkeyRecordItem)
        hotkeyRemoveItem = NSMenuItem(title: "Remove Shortcut", action: #selector(removeHotkey), keyEquivalent: "")
        hotkeyRemoveItem.target = self
        hotkeyRemoveItem.isEnabled = hotkeyKeyCode != UInt32.max
        hotkeyMenu.addItem(hotkeyRemoveItem)
        let hotkeyItem = NSMenuItem(title: "Keyboard Shortcut", action: nil, keyEquivalent: "")
        hotkeyItem.submenu = hotkeyMenu
        settingsMenu.addItem(hotkeyItem)

        // Notifications submenu
        let notifMenu = NSMenu()

        alert100Item = NSMenuItem(title: "100% Alert", action: #selector(toggleAlert100), keyEquivalent: "")
        alert100Item.target = self
        notifMenu.addItem(alert100Item)

        alertLimitItem = NSMenuItem(title: "Usage Limit Alert", action: #selector(toggleAlertLimit), keyEquivalent: "")
        alertLimitItem.target = self
        notifMenu.addItem(alertLimitItem)

        notifMenu.addItem(NSMenuItem.separator())

        // Reset Alarm submenu
        let alarmMenu = NSMenu()
        alarmAfter100Item = NSMenuItem(title: "After 100% session", action: #selector(setAlarmAfter100), keyEquivalent: "")
        alarmAfter100Item.target = self
        alarmMenu.addItem(alarmAfter100Item)

        alarmAfterUsedItem = NSMenuItem(title: "After any used session", action: #selector(setAlarmAfterUsed), keyEquivalent: "")
        alarmAfterUsedItem.target = self
        alarmMenu.addItem(alarmAfterUsedItem)

        alarmAfterAnyItem = NSMenuItem(title: "After any session", action: #selector(setAlarmAfterAny), keyEquivalent: "")
        alarmAfterAnyItem.target = self
        alarmMenu.addItem(alarmAfterAnyItem)

        alarmOffItem = NSMenuItem(title: "Off", action: #selector(setAlarmOff), keyEquivalent: "")
        alarmOffItem.target = self
        alarmMenu.addItem(alarmOffItem)

        alarmMenu.addItem(NSMenuItem.separator())

        alarmSkipItem = NSMenuItem(title: "Skip if previous was 0%", action: #selector(toggleAlarmSkip), keyEquivalent: "")
        alarmSkipItem.target = self
        alarmMenu.addItem(alarmSkipItem)

        let alarmItem = NSMenuItem(title: "Reset Alarm", action: nil, keyEquivalent: "")
        alarmItem.submenu = alarmMenu
        notifMenu.addItem(alarmItem)

        notifMenu.addItem(NSMenuItem.separator())

        // Sound submenu
        let soundMenu = NSMenu()
        soundItems.removeAll()
        let soundNames = ["Tink", "Pop", "Purr", "Funk", "Glass", "Ping", "Morse"]
        for name in soundNames {
            let item = NSMenuItem(title: name, action: #selector(selectSound(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            soundMenu.addItem(item)
            soundItems.append(item)
        }
        let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        soundItem.submenu = soundMenu
        notifMenu.addItem(soundItem)

        let notifItem = NSMenuItem(title: "Notifications", action: nil, keyEquivalent: "")
        notifItem.submenu = notifMenu
        settingsMenu.addItem(notifItem)

        // More submenu — all categories with checkmark = pinned
        moreMenu = NSMenu()
        moreToggleItems.removeAll()
        addMoreSection(provider: .claude, keys: claudeCategoryKeys)
        addMoreSection(provider: .codex, keys: codexCategoryKeys)
        addMoreSection(provider: .cursor, keys: cursorCategoryKeys)
        let moreItem = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        moreItem.submenu = moreMenu
        settingsMenu.addItem(moreItem)

        // Debug Mode submenu — copy latest request/response as formatted JSON or as a curl command
        let debugMenu = NSMenu()
        let debugRequestItem = NSMenuItem(title: "Request", action: #selector(copyDebugRequest), keyEquivalent: "")
        debugRequestItem.target = self
        debugMenu.addItem(debugRequestItem)
        let debugResponseItem = NSMenuItem(title: "Response", action: #selector(copyDebugResponse), keyEquivalent: "")
        debugResponseItem.target = self
        debugMenu.addItem(debugResponseItem)
        let debugCurlItem = NSMenuItem(title: "curl", action: #selector(copyDebugCurl), keyEquivalent: "")
        debugCurlItem.target = self
        debugMenu.addItem(debugCurlItem)
        debugMenu.addItem(NSMenuItem.separator())
        let debugCodexRequestItem = NSMenuItem(
            title: "Codex Request",
            action: #selector(copyCodexDebugRequest),
            keyEquivalent: ""
        )
        debugCodexRequestItem.target = self
        debugMenu.addItem(debugCodexRequestItem)
        let debugCodexResponseItem = NSMenuItem(
            title: "Codex Response",
            action: #selector(copyCodexDebugResponse),
            keyEquivalent: ""
        )
        debugCodexResponseItem.target = self
        debugMenu.addItem(debugCodexResponseItem)
        let debugCursorRequestItem = NSMenuItem(
            title: "Cursor Request",
            action: #selector(copyCursorDebugRequest),
            keyEquivalent: ""
        )
        debugCursorRequestItem.target = self
        debugMenu.addItem(debugCursorRequestItem)
        let debugCursorResponseItem = NSMenuItem(
            title: "Cursor Response",
            action: #selector(copyCursorDebugResponse),
            keyEquivalent: ""
        )
        debugCursorResponseItem.target = self
        debugMenu.addItem(debugCursorResponseItem)
        let debugItem = NSMenuItem(title: "Debug Mode", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        settingsMenu.addItem(debugItem)

        let exportItem = NSMenuItem(title: "Export Data...", action: #selector(exportData), keyEquivalent: "")
        exportItem.target = self
        settingsMenu.addItem(exportItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        // Help submenu
        let helpMenu = NSMenu()

        let claudeUsageItem = NSMenuItem(title: "Claude Usage", action: #selector(openClaudeUsage), keyEquivalent: "")
        claudeUsageItem.target = self
        helpMenu.addItem(claudeUsageItem)

        let apiUsageItem = NSMenuItem(title: "API Usage", action: #selector(openAPIUsage), keyEquivalent: "")
        apiUsageItem.target = self
        helpMenu.addItem(apiUsageItem)

        let githubItem = NSMenuItem(title: "GitHub", action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        helpMenu.addItem(githubItem)

        let authorItem = NSMenuItem(title: "Author: \(appAuthor)", action: #selector(openAuthor), keyEquivalent: "")
        authorItem.target = self
        helpMenu.addItem(authorItem)

        helpMenu.addItem(NSMenuItem.separator())

        let shareItem = NSMenuItem(title: "Share...", action: #selector(shareApp), keyEquivalent: "")
        shareItem.target = self
        helpMenu.addItem(shareItem)

        let updateItem = NSMenuItem(title: "Update…", action: #selector(openUpdateDocs), keyEquivalent: "")
        updateItem.target = self
        helpMenu.addItem(updateItem)

        helpMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        helpMenu.addItem(quitItem)

        let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        menu.addItem(helpMenuItem)

        // Restore checkmark states
        updateIntervalMenu()
        updateNotificationMenu()
        updateAlarmMenu()
        updateSoundMenu()
    }

    func rebuildMenu() {
        buildMenu()
    }

    // MARK: - Usage Sections

    /// Codex rows only appear once a fetch has produced usage data.
    var codexSectionVisible: Bool {
        return codexTrackingEnabled && codexAvailable
    }

    /// Cursor rows only appear once a fetch has produced usage data.
    var cursorSectionVisible: Bool {
        return cursorTrackingEnabled && cursorAvailable
    }

    func providerHeaderItem(_ provider: UsageProvider) -> NSMenuItem {
        let title = providerSectionTitles[provider] ?? ""
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    func addUsageSection(provider: UsageProvider, keys: [String], showsHeader: Bool) {
        let sectionKeys = keys.filter { pinnedKeys.contains($0) }
        guard !sectionKeys.isEmpty else { return }

        if showsHeader {
            if menu.numberOfItems > 0 {
                menu.addItem(NSMenuItem.separator())
            }
            menu.addItem(providerHeaderItem(provider))
        }
        for key in sectionKeys {
            guard let item = usageItems[key] else { continue }
            menu.addItem(item)
            if let rateItem = rateItems[key] {
                menu.addItem(rateItem)
            }
        }
    }

    /// The More submenu always shows headers so same-named categories stay distinguishable.
    func addMoreSection(provider: UsageProvider, keys: [String]) {
        if moreMenu.numberOfItems > 0 {
            moreMenu.addItem(NSMenuItem.separator())
        }
        moreMenu.addItem(providerHeaderItem(provider))
        for key in keys {
            let label = categoryLabel(for: key)
            let item = NSMenuItem(title: label, action: #selector(togglePin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = pinnedKeys.contains(key) ? .on : .off
            moreMenu.addItem(item)
            moreToggleItems[key] = item
        }
    }

    // MARK: - Sleep/Wake

    @objc func handleSleep() {
        timer?.invalidate()
        timer = nil
        alarmCheckTimer?.invalidate()
        alarmCheckTimer = nil
    }

    @objc func handleWake() {
        restartTimer()
        refresh()
    }

    // MARK: - Menu Updates

    func updateIntervalMenu() {
        interval1mItem?.state = refreshInterval == 60 ? .on : .off
        interval5mItem?.state = refreshInterval == 300 ? .on : .off
        interval30mItem?.state = refreshInterval == 1800 ? .on : .off
        interval1hItem?.state = refreshInterval == 3600 ? .on : .off
    }

    func updateNotificationMenu() {
        alert100Item?.state = alert100Enabled ? .on : .off
        alertLimitItem?.state = alertLimitEnabled ? .on : .off
    }

    func updateAlarmMenu() {
        alarmAfter100Item?.state = alarmCondition == 1 ? .on : .off
        alarmAfterUsedItem?.state = alarmCondition == 2 ? .on : .off
        alarmAfterAnyItem?.state = alarmCondition == 3 ? .on : .off
        alarmOffItem?.state = alarmCondition == 0 ? .on : .off
        alarmSkipItem?.state = alarmSkipIfPrevZero ? .on : .off
    }

    func updateSoundMenu() {
        for item in soundItems {
            if let name = item.representedObject as? String {
                item.state = name == selectedSoundName ? .on : .off
            }
        }
    }

    func updateUsageSourceMenu() {
        usageSourceCookiesItem?.state = usageSource == 0 ? .on : .off
        usageSourceOAuthItem?.state = usageSource == 1 ? .on : .off
    }

    func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer?.tolerance = max(10, refreshInterval * 0.1)
    }

    // MARK: - Actions

    @objc func setInterval1m() { refreshInterval = 60 }
    @objc func setInterval5m() { refreshInterval = 300 }
    @objc func setInterval30m() { refreshInterval = 1800 }
    @objc func setInterval1h() { refreshInterval = 3600 }

    @objc func toggleAlert100() {
        alert100Enabled = !alert100Enabled
        updateNotificationMenu()
    }

    @objc func toggleAlertLimit() {
        alertLimitEnabled = !alertLimitEnabled
        updateNotificationMenu()
    }

    @objc func setAlarmAfter100() { alarmCondition = 1 }
    @objc func setAlarmAfterUsed() { alarmCondition = 2 }
    @objc func setAlarmAfterAny() { alarmCondition = 3 }
    @objc func setAlarmOff() { alarmCondition = 0 }

    @objc func toggleAlarmSkip() {
        alarmSkipIfPrevZero = !alarmSkipIfPrevZero
        updateAlarmMenu()
    }

    @objc func toggleColors() {
        colorsEnabled = !colorsEnabled
        refresh()
    }

    @objc func toggleRateInsight() {
        rateInsightEnabled = !rateInsightEnabled
        if rateInsightEnabled { refresh() }
    }

    @objc func toggleAlwaysShowExtraUsage() {
        alwaysShowExtraUsageEnabled = !alwaysShowExtraUsageEnabled
        applyExtraUsageRowVisibility()
    }

    @objc func showUsageGraph() {
        if let existing = graphPanel {
            existing.close()
            graphPanel = nil
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 220),
            styleMask: [.titled, .closable, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Claude Usage — Last 90 Days"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.center()

        let webView = WKWebView(frame: panel.contentView!.bounds)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        panel.contentView?.addSubview(webView)

        let html = generateHeatmapHTML()
        webView.loadHTMLString(html, baseURL: nil)

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        graphPanel = panel
    }

    @objc func recordHotkey() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Record Keyboard Shortcut"
        alert.informativeText = "Press your desired key combination.\nUse at least one modifier (Cmd, Shift, Opt, Ctrl) plus a key."
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        if let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            alert.icon = NSImage(contentsOfFile: iconPath)
        }

        let label = NSTextField(labelWithString: "Waiting for shortcut...")
        label.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        alert.accessoryView = label

        var captured = false
        var capturedKeyCode: UInt32 = 0
        var capturedModifiers: UInt32 = 0

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods.contains(.command) || mods.contains(.option) || mods.contains(.control) {
                let app = NSApplication.shared.delegate as! AppDelegate
                capturedKeyCode = UInt32(event.keyCode)
                capturedModifiers = app.carbonModifiers(from: mods)
                captured = true
                label.stringValue = app.hotkeyDisplayStringFor(keyCode: capturedKeyCode, modifiers: capturedModifiers)
                alert.buttons.first?.performClick(nil)
                return nil
            }
            label.stringValue = "Add a modifier key (Cmd, Opt, Ctrl)"
            return nil
        }

        alert.runModal()
        NSApp.setActivationPolicy(.accessory)

        if let monitor {
            NSEvent.removeMonitor(monitor)
        }

        if captured {
            unregisterGlobalHotkey()
            hotkeyKeyCode = capturedKeyCode
            hotkeyModifiers = capturedModifiers
            saveHotkeyPrefs()
            registerGlobalHotkey()
        }
    }

    @objc func removeHotkey() {
        unregisterGlobalHotkey()
        hotkeyKeyCode = UInt32.max
        hotkeyModifiers = 0
        saveHotkeyPrefs()
        updateHotkeyMenu()
    }

    func hotkeyDisplayStringFor(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Opt") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined(separator: "+")
    }

    @objc func toggleOpenAtLogin() {
        openAtLoginEnabled = !openAtLoginEnabled
    }

    @objc func selectUsageSourceCookies() {
        usageSource = 0
    }

    @objc func selectUsageSourceOAuth() {
        usageSource = 1
    }

    @objc func toggleCodexTracking() {
        codexTrackingEnabled = !codexTrackingEnabled
        guard codexTrackingEnabled else {
            codexAvailable = false
            codexStatusText = nil
            menuBarOwnership.provider = .claude
            saveMenuBarOwnership()
            updateStatusItemTitle()
            rebuildMenu()
            return
        }
        refresh()
    }

    @objc func toggleCursorTracking() {
        cursorTrackingEnabled = !cursorTrackingEnabled
        guard cursorTrackingEnabled else {
            cursorAvailable = false
            cursorStatusText = nil
            if menuBarOwnership.provider == .cursor {
                menuBarOwnership.provider = .claude
            }
            saveMenuBarOwnership()
            updateStatusItemTitle()
            rebuildMenu()
            return
        }
        refresh()
    }

    func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if openAtLoginEnabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {}
        }
    }

    @objc func selectSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        selectedSoundName = name
        playClicks(count: 2, soundName: name)
    }

    @objc func togglePin(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        suppressRebuild = true
        if pinnedKeys.contains(key) {
            pinnedKeys.remove(key)
        } else {
            pinnedKeys.insert(key)
        }
        suppressRebuild = false
        sender.state = pinnedKeys.contains(key) ? .on : .off
        needsMenuRebuild = true
    }

    @objc func openClaudeUsage() {
        if let url = URL(string: "https://claude.ai/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openAPIUsage() {
        if let url = URL(string: "https://platform.claude.com/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openGitHub() {
        if let url = URL(string: "https://github.com/asboyer/claude-usage-swift") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openUpdateDocs() {
        if let url = URL(string: "https://github.com/asboyer/claude-usage-swift#updating") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openAuthor() {
        if let url = URL(string: "https://asboyer.com") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func shareApp() {
        guard let button = statusItem.button else { return }
        let text = "Claude Usage Tracker by \(appAuthor) - a macOS menu bar app that tracks your Claude usage limits"
        let url = URL(string: "https://github.com/asboyer/claude-usage-swift")!
        let picker = NSSharingServicePicker(items: [text, url])
        picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc func copyUsage() {
        let showsHeaders = codexSectionVisible || cursorSectionVisible
        let sections: [(provider: UsageProvider, keys: [String])] = [
            (.claude, claudeCategoryKeys),
            (.codex, codexSectionVisible ? codexCategoryKeys : []),
            (.cursor, cursorSectionVisible ? cursorCategoryKeys : []),
        ]
        var lines: [String] = []

        for (provider, providerKeys) in sections {
            let keys = providerKeys.filter { pinnedKeys.contains($0) }
            guard !keys.isEmpty else { continue }
            if showsHeaders {
                lines.append(providerSectionTitles[provider] ?? "")
            }
            lines.append(contentsOf: keys.compactMap { usageItems[$0] }.filter { !$0.isHidden }.map { $0.title })
        }

        let text = (lines + [updatedItem.title]).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func copyDebugRequest() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastRequestForDebug ?? "", forType: .string)
    }

    @objc func copyDebugResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastResponseForDebug ?? "", forType: .string)
    }

    @objc func copyCodexDebugRequest() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastCodexRequestForDebug ?? "", forType: .string)
    }

    @objc func copyCodexDebugResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastCodexResponseForDebug ?? "", forType: .string)
    }

    @objc func copyCursorDebugRequest() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastCursorRequestForDebug ?? "", forType: .string)
    }

    @objc func copyCursorDebugResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastCursorResponseForDebug ?? "", forType: .string)
    }

    @objc func copyDebugCurl() {
        let ua = lastUserAgentForDebug ?? "curl/8.4.0"
        let script = """
CC_TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w | python3 -c "import sys, json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])")
curl -sS 'https://api.anthropic.com/api/oauth/usage' \\
  -H "Authorization: Bearer $CC_TOKEN" \\
  -H "anthropic-beta: oauth-2025-04-20" \\
  -H "User-Agent: \(ua)"
"""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(script, forType: .string)
    }

    @objc func exportData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "claude_usage_history.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        panel.begin { response in
            defer { NSApp.setActivationPolicy(.accessory) }
            guard response == .OK, let url = panel.url else { return }

            let file = loadHistoryFile()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(file) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func refresh() {
        if !hasData {
            statusItem.button?.title = "..."
        }

        // Both providers are fetched together so status item ownership is resolved
        // from one consistent pair of readings.
        let group = DispatchGroup()
        var claudeUsage: UsageResponse?
        var claudeRateLimited = false
        var codexUsage: CodexUsage?
        var cursorUsage: CursorUsage?

        group.enter()
        fetchClaudeUsage { usage, rateLimited in
            DispatchQueue.main.async {
                claudeUsage = usage
                claudeRateLimited = rateLimited
                group.leave()
            }
        }

        if codexTrackingEnabled {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                fetchCodexUsage { usage in
                    DispatchQueue.main.async {
                        codexUsage = usage
                        group.leave()
                    }
                }
            }
        }

        if cursorTrackingEnabled {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                fetchCursorUsage { usage in
                    DispatchQueue.main.async {
                        cursorUsage = usage
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.updateUI(usage: claudeUsage, rateLimited: claudeRateLimited)
            self.updateCodexUI(codexUsage)
            self.updateCursorUI(cursorUsage)
            self.updateMenuBarOwnership(
                claudeUsage: claudeUsage,
                codexUsage: codexUsage,
                cursorUsage: cursorUsage
            )
            self.updateStatusItemTitle()
        }
    }

    /// Fetches Claude usage from the selected source, falling back from desktop cookies to the OAuth API.
    func fetchClaudeUsage(completion: @escaping (UsageResponse?, Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let strongSelf = self else {
                completion(nil, false)
                return
            }

            let fetchViaOAuth = {
                guard let token = getOAuthToken() else {
                    completion(nil, false)
                    return
                }
                fetchUsage(token: token, completion: completion)
            }

            guard strongSelf.usageSource == 0 else {
                fetchViaOAuth()
                return
            }

            fetchUsageViaClaudeDesktopCookies { usage in
                guard let usage else {
                    fetchViaOAuth()
                    return
                }
                completion(usage, false)
            }
        }
    }

    func tabbedMenuItemString(_ label: String, _ detail: String, color: NSColor? = nil) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 140, options: [:])]
        let full = "\(label)\t\(detail)"
        return NSAttributedString(string: full, attributes: [
            .paragraphStyle: paragraph,
            .font: NSFont.menuFont(ofSize: 14),
            .foregroundColor: color ?? NSColor.labelColor,
        ])
    }

    func severityColor(utilization: Double, resetsAt: String?, windowSeconds: TimeInterval) -> NSColor? {
        guard colorsEnabled, utilization > 0 else { return nil }
        if utilization >= 100 {
            return NSColor(calibratedHue: 0, saturation: 0.8, brightness: 1.0, alpha: 1.0)
        }

        guard let resetStr = resetsAt,
              let resetDate = isoFormatter.date(from: resetStr) ?? isoFormatterNoFrac.date(from: resetStr) else {
            return nil
        }

        let remaining = max(resetDate.timeIntervalSince(Date()), 0)
        let elapsedFraction = max((windowSeconds - remaining) / windowSeconds, 0.10)
        let projected = utilization / elapsedFraction

        var hue: CGFloat
        let saturation: CGFloat
        let brightness: CGFloat

        if projected <= 80 {
            hue = 120.0 / 360.0
            saturation = 0.8
            brightness = 1.0
        } else if projected <= 105 {
            let t = CGFloat((projected - 80) / 25.0)
            hue = CGFloat(120.0 - 65.0 * Double(t)) / 360.0
            saturation = 0.8 + 0.05 * t
            brightness = 1.0
        } else if projected <= 140 {
            let t = CGFloat((projected - 105) / 35.0)
            hue = CGFloat(55.0 - 40.0 * Double(t)) / 360.0
            saturation = 0.85 + 0.05 * t
            brightness = 1.0 - 0.1 * t
        } else {
            hue = 0
            saturation = 0.9
            brightness = 0.9
        }

        if utilization >= 90 {
            hue = min(hue, 25.0 / 360.0)
        } else if utilization >= 80 {
            hue = min(hue, 55.0 / 360.0)
        }

        return NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    }

    func dimmedMenuItemString(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    func updateRateItem(key: String, utilization: Double, isWeekly: Bool) {
        guard let item = rateItems[key] else { return }
        guard rateInsightEnabled else {
            item.isHidden = true
            return
        }
        let rate = rateForCategory(key, currentUtil: utilization, isWeekly: isWeekly)
        guard let value = isWeekly ? rate.perDay : rate.perHour else {
            item.isHidden = true
            return
        }

        let unitLabel = isWeekly ? "day" : "hr"
        let rateText = String(format: "  %.0f%%/%@", value, unitLabel)
        let title = "\(rateText) · \(rate.descriptor)"
        let color = colorsEnabled ? rateDescriptorColor(rate.descriptor) : NSColor.secondaryLabelColor

        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.menuFont(ofSize: 12),
            .foregroundColor: color,
        ])
        item.title = title
        item.isHidden = false
    }

    func updateUsageItem(key: String, limit: UsageLimit?, windowSeconds: TimeInterval = 0) {
        guard let item = usageItems[key] else { return }
        let label = categoryLabel(for: key)
        if let limit {
            let pct = Int(limit.utilization)
            let reset = limit.resets_at.map { formatReset($0) } ?? "--"
            item.title = "\(label): \(pct)% (resets \(reset))"
            let color = windowSeconds > 0
                ? severityColor(utilization: limit.utilization, resetsAt: limit.resets_at, windowSeconds: windowSeconds)
                : nil
            item.attributedTitle = tabbedMenuItemString("\(label): \(pct)%", "resets \(reset)", color: color)

            let isWeekly = key != "five_hour" && key != "codex_five_hour"
            recordUsageSample(key, utilization: limit.utilization)
            updateRateItem(key: key, utilization: limit.utilization, isWeekly: isWeekly)
        } else {
            item.title = "\(label): --"
            item.attributedTitle = nil
            rateItems[key]?.isHidden = true
        }
    }

    /// The scoped weekly row is labeled by the API, so its title has to follow the fetched model name.
    func updateScopedWeeklyItem(_ scoped: (label: String?, limit: UsageLimit)?) {
        if let label = scoped?.label {
            dynamicCategoryLabels[scopedWeeklyKey] = label
            moreToggleItems[scopedWeeklyKey]?.title = label
        }
        lastScopedWeeklyUtilization = scoped?.limit.utilization
        updateUsageItem(key: scopedWeeklyKey, limit: scoped?.limit, windowSeconds: 7 * 86400)
    }

    /// Hides the Extra row until credits are actually accruing, unless pinned open by the setting.
    func applyExtraUsageRowVisibility() {
        let shouldShow = ExtraUsageRowVisibility.shouldShow(
            alwaysShow: alwaysShowExtraUsageEnabled,
            spentCredits: lastSpentCredits,
            scopedWeeklyUtilization: lastScopedWeeklyUtilization
        )
        usageItems["extra_usage"]?.isHidden = !shouldShow
        if !shouldShow {
            rateItems["extra_usage"]?.isHidden = true
        }
    }

    func updateUI(usage: UsageResponse?, rateLimited: Bool = false) {
        isRateLimited = rateLimited
        rateLimitItem?.isHidden = !rateLimited
        if rateLimited {
            rateLimitItem?.attributedTitle = NSAttributedString(
                string: "Rate limited. Try again later.",
                attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.menuFont(ofSize: 14)]
            )
        }

        guard let usage else {
            hasData = false
            claudeStatusText = nil
            return
        }

        lastFetchDate = Date()
        updateUsageItem(key: "five_hour", limit: usage.five_hour, windowSeconds: 5 * 3600)
        updateUsageItem(key: "seven_day", limit: usage.seven_day, windowSeconds: 7 * 86400)
        updateScopedWeeklyItem(scopedWeeklyLimit(usage))
        updateUsageItem(key: "seven_day_opus", limit: usage.seven_day_opus, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_sonnet", limit: usage.seven_day_sonnet, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_oauth_apps", limit: usage.seven_day_oauth_apps, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_cowork", limit: usage.seven_day_cowork, windowSeconds: 7 * 86400)

        // `monthly_limit` and `utilization` are null on plans that only meter spend, so the
        // row needs `used_credits` alone.
        if let extra = usage.extra_usage, extra.is_enabled, let used = extra.used_credits {
            lastSpentCredits = used
            let label = categoryLabel(for: "extra_usage")
            let spendText = ExtraUsageFormatter.formatCredits(used, decimalPlaces: extra.decimal_places)
            usageItems["extra_usage"]?.title = "\(label): \(spendText)"
            usageItems["extra_usage"]?.attributedTitle = tabbedMenuItemString("\(label): \(spendText)", "")
            if let util = extra.utilization {
                recordUsageSample("extra_usage", utilization: util)
                updateRateItem(key: "extra_usage", utilization: util, isWeekly: true)
            } else {
                rateItems["extra_usage"]?.isHidden = true
            }
        } else {
            lastSpentCredits = nil
            usageItems["extra_usage"]?.title = "Extra: --"
            usageItems["extra_usage"]?.attributedTitle = nil
            rateItems["extra_usage"]?.isHidden = true
        }

        if let fiveHour = usage.five_hour {
            let pct = Int(fiveHour.utilization)
            let reset = fiveHour.resets_at.map { formatReset($0) } ?? "--"

            if let resetStr = fiveHour.resets_at {
                let parsedDate = isoFormatter.date(from: resetStr) ?? isoFormatterNoFrac.date(from: resetStr)
                if let newResetDate = parsedDate {
                    if let lastReset = lastKnownResetDate, abs(newResetDate.timeIntervalSince(lastReset)) > 60 {
                        triggerAlarmIfNeeded(endedSessionUtil: lastSessionFinalUtil)
                    }
                    lastKnownResetDate = newResetDate
                    scheduleAlarmCheckTimer(for: newResetDate)
                }
            }

            let newUtil = fiveHour.utilization
            let priorUtil = previousFiveHourUtil >= 0 ? previousFiveHourUtil : nil
            if previousFiveHourUtil >= 0 && previousFiveHourUtil < 100 && newUtil >= 100 {
                if alert100Enabled {
                    playClicks(count: 2, soundName: selectedSoundName)
                }
            }
            lastSessionFinalUtil = newUtil
            previousSessionHadUsage = newUtil > 0
            previousFiveHourUtil = newUtil

            let extra = usage.extra_usage
            let spent = (extra?.is_enabled == true) ? extra?.used_credits : nil
            statusDisplayMode = StatusDisplayModeSelector.select(
                previous: statusDisplayMode,
                fiveHourUtilization: newUtil,
                previousFiveHourUtilization: priorUtil,
                spentCredits: spent,
                previousSpentCredits: previousSpentCredits
            )
            previousSpentCredits = spent

            let excl = alarmCondition != 0 ? "!" : ""
            if let spent, statusDisplayMode == .overage || pct >= 100 {
                currentPct = String(format: "$%.2f%@", spent / 100, excl)
            } else if pct >= 100 {
                currentPct = "\(reset)\(excl)"
            } else {
                currentPct = "\(pct)%"
            }

            hasData = true
            claudeStatusText = currentPct
            statusItem.length = NSStatusItem.variableLength
        }

        if let extra = usage.extra_usage, let util = extra.utilization {
            if previousExtraUtil >= 0 && previousExtraUtil < 100 && util >= 100 {
                if alertLimitEnabled {
                    playClicks(count: 3, soundName: selectedSoundName)
                }
            }
            previousExtraUtil = util
        }

        applyExtraUsageRowVisibility()

        let stale = isDataStale() ? " (stale)" : ""
        let updatedText = "Updated: \(timeFormatter.string(from: Date()))\(stale)"
        updatedItem.title = updatedText
        updatedItem.attributedTitle = dimmedMenuItemString(updatedText)
    }

    // MARK: - Codex

    func updateCodexUI(_ usage: CodexUsage?) {
        let wasAvailable = codexAvailable

        guard codexTrackingEnabled, let weekly = usage?.weekly else {
            codexAvailable = false
            codexStatusText = nil
            for key in codexCategoryKeys {
                usageItems[key]?.title = "\(categoryLabel(for: key)): --"
                usageItems[key]?.attributedTitle = nil
                rateItems[key]?.isHidden = true
            }
            rebuildMenuIfSectionVisibilityChanged(wasAvailable: wasAvailable, isAvailable: codexAvailable)
            return
        }

        codexAvailable = true
        updateCodexUsageItem(
            key: "codex_five_hour",
            window: usage?.fiveHour,
            defaultWindowSeconds: CodexWindowSelector.fiveHourWindowSeconds
        )
        updateCodexUsageItem(
            key: "codex_weekly",
            window: weekly,
            defaultWindowSeconds: CodexWindowSelector.weeklyWindowSeconds
        )

        // The menu bar tracks the session window, matching how Claude usage is displayed,
        // and falls back to weekly on plans that report no session limit.
        let statusWindow = usage?.fiveHour ?? weekly
        codexStatusText = statusText(percent: statusWindow.usedPercent, resetsAt: statusWindow.resetsAt)

        rebuildMenuIfSectionVisibilityChanged(wasAvailable: wasAvailable, isAvailable: codexAvailable)
    }

    private func updateCodexUsageItem(
        key: String,
        window: CodexRateWindow?,
        defaultWindowSeconds: TimeInterval
    ) {
        usageItems[key]?.isHidden = window == nil
        guard let window else {
            updateUsageItem(key: key, limit: nil)
            return
        }
        let limit = UsageLimit(
            utilization: window.usedPercent,
            resets_at: window.resetsAt.map { isoFormatter.string(from: $0) }
        )
        let windowSeconds = window.windowSeconds > 0 ? window.windowSeconds : defaultWindowSeconds
        updateUsageItem(key: key, limit: limit, windowSeconds: windowSeconds)
    }

    /// An exhausted window shows when it frees up instead of a flat 100%.
    private func statusText(percent: Double, resetsAt: Date?) -> String? {
        let pct = Int(percent)
        if pct >= 100, let resetsAt {
            return formatResetDate(resetsAt)
        }
        return "\(pct)%"
    }

    private func rebuildMenuIfSectionVisibilityChanged(wasAvailable: Bool, isAvailable: Bool) {
        guard menuReady, wasAvailable != isAvailable else { return }
        rebuildMenu()
    }

    // MARK: - Cursor

    func updateCursorUI(_ usage: CursorUsage?) {
        let wasAvailable = cursorAvailable

        guard cursorTrackingEnabled, let usage else {
            cursorAvailable = false
            cursorStatusText = nil
            for key in cursorCategoryKeys {
                usageItems[key]?.title = "\(categoryLabel(for: key)): --"
                usageItems[key]?.attributedTitle = nil
                rateItems[key]?.isHidden = true
            }
            rebuildMenuIfSectionVisibilityChanged(wasAvailable: wasAvailable, isAvailable: cursorAvailable)
            return
        }

        cursorAvailable = true
        updateCursorUsageItem(key: "cursor_models", percent: usage.cursorModelsPercent, usage: usage)
        updateCursorUsageItem(key: "cursor_other_models", percent: usage.otherModelsPercent, usage: usage)

        // Both buckets reset on the same billing cycle, so the menu bar tracks whichever
        // of the two is closest to running out.
        cursorStatusText = statusText(percent: usage.highestPercent.rounded(.up), resetsAt: usage.cycleEndsAt)

        rebuildMenuIfSectionVisibilityChanged(wasAvailable: wasAvailable, isAvailable: cursorAvailable)
    }

    private func updateCursorUsageItem(key: String, percent: Double, usage: CursorUsage) {
        // Cursor's dashboard rounds these buckets up, so a bucket with any spend never reads 0%.
        let limit = UsageLimit(
            utilization: percent.rounded(.up),
            resets_at: usage.cycleEndsAt.map { isoFormatter.string(from: $0) }
        )
        updateUsageItem(key: key, limit: limit, windowSeconds: usage.cycleSeconds)
    }

    // MARK: - Status Item

    func updateMenuBarOwnership(
        claudeUsage: UsageResponse?,
        codexUsage: CodexUsage?,
        cursorUsage: CursorUsage?
    ) {
        menuBarOwnership = MenuBarOwnershipResolver.resolve(
            current: menuBarOwnership,
            utilizations: [
                .claude: claudeUsage?.five_hour?.utilization,
                .codex: codexTrackingEnabled
                    ? (codexUsage?.fiveHour ?? codexUsage?.weekly)?.usedPercent
                    : nil,
                .cursor: cursorTrackingEnabled ? cursorUsage?.highestPercent : nil,
            ]
        )
        saveMenuBarOwnership()
    }

    func updateStatusItemTitle() {
        let statusTexts: [UsageProvider: String] = [
            .claude: claudeStatusText,
            .codex: codexStatusText,
            .cursor: cursorStatusText,
        ].compactMapValues { $0 }

        guard !statusTexts.isEmpty else {
            statusItem.button?.title = "..."
            return
        }
        if let owned = statusTexts[menuBarOwnership.provider] {
            statusItem.button?.title = owned
            return
        }
        // The owning provider has no reading yet, so fall back in declaration order.
        statusItem.button?.title = UsageProvider.allCases.compactMap { statusTexts[$0] }.first ?? "..."
    }

    func loadMenuBarOwnership() -> MenuBarOwnership {
        let defaults = UserDefaults.standard
        let provider = UsageProvider(rawValue: defaults.string(forKey: "menuBarProvider") ?? "") ?? .claude
        // Baselines from before this was a dictionary are dropped; the next refresh restores them.
        let stored = defaults.dictionary(forKey: "menuBarLastUtilizations") as? [String: Double] ?? [:]
        var lastUtilizations: [UsageProvider: Double] = [:]
        for (rawValue, utilization) in stored {
            guard let storedProvider = UsageProvider(rawValue: rawValue) else { continue }
            lastUtilizations[storedProvider] = utilization
        }
        return MenuBarOwnership(provider: provider, lastUtilizations: lastUtilizations)
    }

    func saveMenuBarOwnership() {
        let defaults = UserDefaults.standard
        defaults.set(menuBarOwnership.provider.rawValue, forKey: "menuBarProvider")
        var stored: [String: Double] = [:]
        for (provider, utilization) in menuBarOwnership.lastUtilizations {
            stored[provider.rawValue] = utilization
        }
        defaults.set(stored, forKey: "menuBarLastUtilizations")
    }

    func isDataStale() -> Bool {
        guard let last = lastFetchDate else { return false }
        return Date().timeIntervalSince(last) > refreshInterval * 2
    }

    func scheduleAlarmCheckTimer(for resetDate: Date) {
        alarmCheckTimer?.invalidate()
        let fireDate = resetDate.addingTimeInterval(1)
        let delay = fireDate.timeIntervalSinceNow
        guard delay > 0 else { return }
        alarmCheckTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }

    func triggerAlarmIfNeeded(endedSessionUtil: Double) {
        guard alarmCondition != 0 else { return }
        if alarmSkipIfPrevZero && !previousSessionHadUsage { return }

        var shouldAlarm = false
        switch alarmCondition {
        case 1: shouldAlarm = endedSessionUtil >= 100
        case 2: shouldAlarm = endedSessionUtil > 0
        case 3: shouldAlarm = true
        default: break
        }

        guard shouldAlarm else { return }
        guard !alarmIsPlaying else { return }

        alarmIsPlaying = true
        playAlarmBursts(soundName: selectedSoundName, checkMuted: { false }) { [weak self] in
            self?.alarmIsPlaying = false
        }
    }
}
