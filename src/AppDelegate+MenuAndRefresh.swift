import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import WebKit

extension AppDelegate {
    func buildMenu() {
        menu.removeAllItems()

        // Pinned usage items with rate sub-items (in canonical order)
        for key in allCategoryKeys {
            if pinnedKeys.contains(key), let item = usageItems[key] {
                menu.addItem(item)
                if let rateItem = rateItems[key] {
                    menu.addItem(rateItem)
                }
            }
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
        for key in allCategoryKeys {
            let label = categoryLabels[key] ?? key
            let item = NSMenuItem(title: label, action: #selector(togglePin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = pinnedKeys.contains(key) ? .on : .off
            moreMenu.addItem(item)
            moreToggleItems[key] = item
        }
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

        let authorItem = NSMenuItem(title: "Author", action: #selector(openAuthor), keyEquivalent: "")
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
        let text = "Claude Usage Tracker - a macOS menu bar app that tracks your Claude usage limits"
        let url = URL(string: "https://github.com/asboyer/claude-usage-swift")!
        let picker = NSSharingServicePicker(items: [text, url])
        picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc func copyUsage() {
        let lines = allCategoryKeys
            .filter { pinnedKeys.contains($0) }
            .compactMap { usageItems[$0]?.title }
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

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let strongSelf = self else { return }
            let source = strongSelf.usageSource

            if source == 0 {
                fetchUsageViaClaudeDesktopCookies { usage in
                    if let usage {
                        DispatchQueue.main.async {
                            self?.updateUI(usage: usage, rateLimited: false)
                        }
                        return
                    }

                    guard let token = getOAuthToken() else {
                        DispatchQueue.main.async {
                            self?.hasData = false
                            self?.statusItem.button?.title = "..."
                        }
                        return
                    }

                    fetchUsage(token: token) { usage, rateLimited in
                        DispatchQueue.main.async {
                            self?.updateUI(usage: usage, rateLimited: rateLimited)
                        }
                    }
                }
            } else {
                guard let token = getOAuthToken() else {
                    DispatchQueue.main.async {
                        self?.hasData = false
                        self?.statusItem.button?.title = "..."
                    }
                    return
                }

                fetchUsage(token: token) { usage, rateLimited in
                    DispatchQueue.main.async {
                        self?.updateUI(usage: usage, rateLimited: rateLimited)
                    }
                }
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
        let label = categoryLabels[key] ?? key
        if let limit {
            let pct = Int(limit.utilization)
            let reset = limit.resets_at.map { formatReset($0) } ?? "--"
            item.title = "\(label): \(pct)% (resets \(reset))"
            let color = windowSeconds > 0
                ? severityColor(utilization: limit.utilization, resetsAt: limit.resets_at, windowSeconds: windowSeconds)
                : nil
            item.attributedTitle = tabbedMenuItemString("\(label): \(pct)%", "resets \(reset)", color: color)

            let isWeekly = key != "five_hour"
            recordUsageSample(key, utilization: limit.utilization)
            updateRateItem(key: key, utilization: limit.utilization, isWeekly: isWeekly)
        } else {
            item.title = "\(label): --"
            item.attributedTitle = nil
            rateItems[key]?.isHidden = true
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
            statusItem.button?.title = "..."
            return
        }

        lastFetchDate = Date()
        updateUsageItem(key: "five_hour", limit: usage.five_hour, windowSeconds: 5 * 3600)
        updateUsageItem(key: "seven_day", limit: usage.seven_day, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_opus", limit: usage.seven_day_opus, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_sonnet", limit: usage.seven_day_sonnet, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_oauth_apps", limit: usage.seven_day_oauth_apps, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_cowork", limit: usage.seven_day_cowork, windowSeconds: 7 * 86400)

        if let extra = usage.extra_usage, extra.is_enabled,
           let used = extra.used_credits, let limit = extra.monthly_limit, let util = extra.utilization {
            let extraText = String(format: "Extra: $%.2f/$%.0f", used / 100, limit / 100)
            let extraDetail = String(format: "%.0f%%", util)
            usageItems["extra_usage"]?.title = String(format: "Extra: $%.2f/$%.0f (%.0f%%)", used / 100, limit / 100, util)
            usageItems["extra_usage"]?.attributedTitle = tabbedMenuItemString(extraText, extraDetail)
            recordUsageSample("extra_usage", utilization: util)
            updateRateItem(key: "extra_usage", utilization: util, isWeekly: true)
        } else {
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
            if previousFiveHourUtil >= 0 && previousFiveHourUtil < 100 && newUtil >= 100 {
                if alert100Enabled {
                    playClicks(count: 2, soundName: selectedSoundName)
                }
            }
            lastSessionFinalUtil = newUtil
            previousSessionHadUsage = newUtil > 0
            previousFiveHourUtil = newUtil

            let excl = alarmCondition != 0 ? "!" : ""
            if pct >= 100 {
                if let extra = usage.extra_usage, extra.is_enabled, let spent = extra.used_credits {
                    let dollars = spent / 100
                    currentPct = String(format: "$%.2f%@", dollars, excl)
                } else {
                    currentPct = "\(reset)\(excl)"
                }
            } else {
                currentPct = "\(pct)%"
            }

            hasData = true
            statusItem.length = NSStatusItem.variableLength
            statusItem.button?.title = currentPct
        }

        if let extra = usage.extra_usage, let util = extra.utilization {
            if previousExtraUtil >= 0 && previousExtraUtil < 100 && util >= 100 {
                if alertLimitEnabled {
                    playClicks(count: 3, soundName: selectedSoundName)
                }
            }
            previousExtraUtil = util
        }

        let stale = isDataStale() ? " (stale)" : ""
        let updatedText = "Updated: \(timeFormatter.string(from: Date()))\(stale)"
        updatedItem.title = updatedText
        updatedItem.attributedTitle = dimmedMenuItemString(updatedText)
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
