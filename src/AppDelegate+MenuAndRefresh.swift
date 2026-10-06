import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import WebKit

extension AppDelegate {
    func buildMenu() {
        menu.removeAllItems()

        // Pinned usage items with rate sub-items, grouped by provider
        let showsProviderSections = codexSectionVisible || cursorSectionVisible || opencodeSectionVisible
        addUsageSection(provider: .claude, keys: claudeCategoryKeys, showsHeader: showsProviderSections)
        if codexSectionVisible {
            addUsageSection(provider: .codex, keys: codexCategoryKeys, showsHeader: true)
        }
        if cursorSectionVisible {
            addUsageSection(provider: .cursor, keys: cursorCategoryKeys, showsHeader: true)
        }
        if opencodeSectionVisible {
            addOpencodeSection()
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(rateLimitItem)
        menu.addItem(updatedItem)

        let breakdownItem = NSMenuItem(
            title: "Usage Breakdown", action: #selector(showUsageBreakdown), keyEquivalent: "g"
        )
        breakdownItem.target = self
        breakdownItem.keyEquivalentModifierMask = []
        menu.addItem(breakdownItem)

        let historyItem = NSMenuItem(
            title: "Spend History", action: #selector(showSpendHistory), keyEquivalent: "h"
        )
        historyItem.target = self
        historyItem.keyEquivalentModifierMask = []
        menu.addItem(historyItem)

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

        // Codex Credit Price submenu — prices the Codex overage estimate
        let creditPriceMenu = NSMenu()
        codexCreditPriceItems = CodexOverageCore.pricePresets.map { price in
            let formatted = CodexOverageCore.formatPrice(price)
            let title = price == CodexOverageCore.defaultPricePerCredit ? "\(formatted) (OpenAI list price)" : formatted
            let item = NSMenuItem(title: title, action: #selector(selectCodexCreditPrice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = price
            creditPriceMenu.addItem(item)
            return item
        }
        creditPriceMenu.addItem(NSMenuItem.separator())
        codexCreditPriceCustomItem = NSMenuItem(
            title: "Custom…", action: #selector(enterCustomCodexCreditPrice), keyEquivalent: ""
        )
        codexCreditPriceCustomItem.target = self
        creditPriceMenu.addItem(codexCreditPriceCustomItem)
        let creditPriceItem = NSMenuItem(title: "Codex Credit Price", action: nil, keyEquivalent: "")
        creditPriceItem.submenu = creditPriceMenu
        settingsMenu.addItem(creditPriceItem)

        showCodexCreditsItem = NSMenuItem(
            title: "Show Codex Credits", action: #selector(toggleShowCodexCredits), keyEquivalent: ""
        )
        showCodexCreditsItem.target = self
        showCodexCreditsItem.state = showCodexCredits ? .on : .off
        settingsMenu.addItem(showCodexCreditsItem)

        // Codex Extra Usage Window submenu — how far back the Codex Extra row counts
        let overagePeriodMenu = NSMenu()
        codexOveragePeriodItems = CodexOveragePeriod.allCases.map { period in
            let title = period == .defaultPeriod ? "\(period.menuTitle) (default)" : period.menuTitle
            let item = NSMenuItem(title: title, action: #selector(selectCodexOveragePeriod(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = period.rawValue
            overagePeriodMenu.addItem(item)
            return item
        }
        let overagePeriodItem = NSMenuItem(title: "Codex Extra Usage Window", action: nil, keyEquivalent: "")
        overagePeriodItem.submenu = overagePeriodMenu
        settingsMenu.addItem(overagePeriodItem)

        cursorTrackingItem = NSMenuItem(
            title: "Track Cursor Usage",
            action: #selector(toggleCursorTracking),
            keyEquivalent: ""
        )
        cursorTrackingItem.target = self
        cursorTrackingItem.state = cursorTrackingEnabled ? .on : .off
        settingsMenu.addItem(cursorTrackingItem)

        opencodeTrackingItem = NSMenuItem(
            title: "Track Opencode",
            action: #selector(toggleOpencodeTracking),
            keyEquivalent: ""
        )
        opencodeTrackingItem.target = self
        opencodeTrackingItem.state = opencodeTrackingEnabled ? .on : .off
        settingsMenu.addItem(opencodeTrackingItem)

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
        updateCodexCreditPriceMenu()
        updateCodexOveragePeriodMenu()
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

    /// Opencode rows only appear once a read has found models that actually cost money.
    var opencodeSectionVisible: Bool {
        return opencodeTrackingEnabled && !(opencodeUsage?.models.isEmpty ?? true)
    }

    /// Lists month-to-date spend per model, collapsed to the priciest few until "More" is clicked.
    /// Unlike the other providers these rows are discovered at runtime, so they are built fresh
    /// on every rebuild rather than kept in `usageItems`.
    func addOpencodeSection() {
        guard let usage = opencodeUsage else { return }

        if menu.numberOfItems > 0 {
            menu.addItem(NSMenuItem.separator())
        }
        menu.addItem(providerHeaderItem(.opencode))

        let collapsedCount = OpencodeUsageCore.collapsedModelCount
        let hasHiddenModels = usage.models.count > collapsedCount
        let shown = opencodeExpanded ? usage.models : Array(usage.models.prefix(collapsedCount))

        for model in shown {
            let cost = OpencodeUsageCore.formatCost(model.costUSD)
            // `noop` keeps these rows looking like the other providers' usage rows,
            // which are actionless but not greyed out.
            let item = NSMenuItem(
                title: "\(model.displayName): \(cost)", action: #selector(noop), keyEquivalent: "")
            item.target = self
            item.attributedTitle = tabbedMenuItemString(model.displayName, cost)
            menu.addItem(item)
        }

        guard hasHiddenModels else { return }
        let toggle = NSMenuItem(
            title: opencodeExpanded ? "Less" : "More",
            action: #selector(toggleOpencodeExpanded),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
    }

    /// Clicking a menu item always dismisses the menu, so the expanded list is reopened
    /// immediately — otherwise the click would look like it did nothing.
    @objc func toggleOpencodeExpanded() {
        opencodeExpanded.toggle()
        rebuildMenu()
        DispatchQueue.main.async { [weak self] in
            self?.showMenu()
        }
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

    @objc func showUsageBreakdown() {
        if let existing = breakdownPanel {
            existing.close()
            breakdownPanel = nil
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .resizable, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Usage Breakdown"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.center()

        let webView = WKWebView(frame: panel.contentView!.bounds)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        panel.contentView?.addSubview(webView)

        // The heatmap renders immediately; reading every recent transcript takes long enough
        // that doing it on the main thread would stall the panel, so the summary fills in after.
        breakdownNavigation = nil
        webView.loadHTMLString(generateUsageBreakdownHTML(breakdown: nil), baseURL: nil)
        let windowHours = ClaudeCodeTranscripts.defaultWindowHours
        // The capture list belongs on the scan closure, not the hop back: it is the scan that
        // outlives a panel the user closes, and a strong capture here would pin the whole web view.
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak panel, weak webView] in
            let requests = ClaudeCodeTranscripts.recentRequests(windowHours: windowHours)
            let breakdown = UsageBreakdownBuilder.build(from: requests, windowHours: windowHours)
            DispatchQueue.main.async {
                guard let self, panel != nil, let webView else { return }
                self.breakdownNavigation = webView.loadHTMLString(
                    generateUsageBreakdownHTML(breakdown: breakdown), baseURL: nil
                )
            }
        }

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        breakdownPanel = panel
    }

    @objc func showSpendHistory() {
        spendHistoryPanel?.close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .resizable, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Spend"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.center()

        let webView = WKWebView(frame: panel.contentView!.bounds)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        panel.contentView?.addSubview(webView)

        // One snapshot per opening: a placeholder while the scan catches up, then the result.
        webView.loadHTMLString(generateSpendHistoryHTML(ledger: nil, pricePerCredit: 0), baseURL: nil)
        let price = codexCreditPrice
        let includeCodex = codexTrackingEnabled
        let includeOpencode = opencodeTrackingEnabled
        DispatchQueue.global(qos: .userInitiated).async { [weak panel, weak webView] in
            let ledger = rescanSpendLedger(includeCodex: includeCodex, includeOpencode: includeOpencode)
            DispatchQueue.main.async {
                guard panel != nil, let webView else { return }
                webView.loadHTMLString(generateSpendHistoryHTML(ledger: ledger, pricePerCredit: price), baseURL: nil)
            }
        }

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        spendHistoryPanel = panel
    }

    /// Keeps the ledger ahead of Claude Code's transcript cleanup even if the panel is never opened.
    func rescanSpendLedgerIfStale() {
        guard !spendLedgerScanInFlight else { return }
        if let lastScan = loadSpendLedger().lastScan, Date().timeIntervalSince(lastScan) < spendLedgerRescanInterval {
            return
        }
        spendLedgerScanInFlight = true
        let includeCodex = codexTrackingEnabled
        let includeOpencode = opencodeTrackingEnabled
        DispatchQueue.global(qos: .utility).async { [weak self] in
            rescanSpendLedger(includeCodex: includeCodex, includeOpencode: includeOpencode)
            DispatchQueue.main.async { self?.spendLedgerScanInFlight = false }
        }
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

    @objc func toggleOpencodeTracking() {
        opencodeTrackingEnabled = !opencodeTrackingEnabled
        guard opencodeTrackingEnabled else {
            opencodeUsage = nil
            opencodeStatusText = nil
            opencodeExpanded = false
            if menuBarOwnership.provider == .opencode {
                menuBarOwnership.provider = .claude
            }
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
        let showsHeaders = codexSectionVisible || cursorSectionVisible || opencodeSectionVisible
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

        // Copy every model, not just the collapsed few — the clipboard has no "More" to click.
        if let usage = opencodeUsage, opencodeSectionVisible {
            lines.append(providerSectionTitles[.opencode] ?? "")
            lines.append(
                contentsOf: usage.models.map {
                    "\($0.displayName): \(OpencodeUsageCore.formatCost($0.costUSD))"
                })
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
        rescanSpendLedgerIfStale()

        // Both providers are fetched together so status item ownership is resolved
        // from one consistent pair of readings.
        let group = DispatchGroup()
        var claudeUsage: UsageResponse?
        var claudeRateLimited = false
        var codexUsage: CodexUsage?
        var cursorUsage: CursorUsage?
        var opencodeUsageResult: OpencodeUsage?

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

        if opencodeTrackingEnabled {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                fetchOpencodeUsage { usage in
                    DispatchQueue.main.async {
                        opencodeUsageResult = usage
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.updateUI(usage: claudeUsage, rateLimited: claudeRateLimited)
            self.updateCodexUI(codexUsage)
            self.refreshCodexOverage(codexUsage)
            self.updateCursorUI(cursorUsage)
            self.updateOpencodeUI(opencodeUsageResult)
            self.updateMenuBarOwnership(
                claudeUsage: claudeUsage,
                codexUsage: codexUsage,
                cursorUsage: cursorUsage,
                opencodeUsage: opencodeUsageResult
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

        // Plans without a per-model weekly limit never return this entry; hide the row
        // rather than leave a permanent "Model: --".
        usageItems[scopedWeeklyKey]?.isHidden = scoped == nil
        if scoped == nil {
            rateItems[scopedWeeklyKey]?.isHidden = true
        }
    }

    /// Hides the Extra row until a weekly limit is exhausted, unless pinned open by the setting.
    func applyExtraUsageRowVisibility() {
        let shouldShow = ExtraUsageRowVisibility.shouldShow(
            alwaysShow: alwaysShowExtraUsageEnabled,
            scopedWeeklyUtilization: lastScopedWeeklyUtilization,
            overallWeeklyUtilization: lastOverallWeeklyUtilization
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
        lastOverallWeeklyUtilization = usage.seven_day?.utilization
        updateUsageItem(key: "seven_day", limit: usage.seven_day, windowSeconds: 7 * 86400)
        updateScopedWeeklyItem(scopedWeeklyLimit(usage))
        updateUsageItem(key: "seven_day_opus", limit: usage.seven_day_opus, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_sonnet", limit: usage.seven_day_sonnet, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_oauth_apps", limit: usage.seven_day_oauth_apps, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_cowork", limit: usage.seven_day_cowork, windowSeconds: 7 * 86400)

        // `monthly_limit` and `utilization` are null on plans that only meter spend, so the
        // row needs `used_credits` alone.
        if let extra = usage.extra_usage, extra.is_enabled, let used = extra.used_credits {
            let label = categoryLabel(for: "extra_usage")
            let spendText = ExtraUsageFormatter.formatCredits(used, decimalPlaces: extra.decimal_places)
            let dollars = used / pow(10.0, Double(max(extra.decimal_places ?? 2, 0)))
            DispatchQueue.global(qos: .utility).async { recordClaudeExtraSpend(dollars: dollars) }
            usageItems["extra_usage"]?.title = "\(label): \(spendText)"
            usageItems["extra_usage"]?.attributedTitle = tabbedMenuItemString("\(label): \(spendText)", "")
            if let util = extra.utilization {
                recordUsageSample("extra_usage", utilization: util)
                updateRateItem(key: "extra_usage", utilization: util, isWeekly: true)
            } else {
                rateItems["extra_usage"]?.isHidden = true
            }
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
            codexStatusWindow = nil
            codexOverage = nil
            for key in codexCategoryKeys {
                usageItems[key]?.title = "\(categoryLabel(for: key)): --"
                usageItems[key]?.attributedTitle = nil
                rateItems[key]?.isHidden = true
            }
            usageItems[codexExtraKey]?.isHidden = true
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
        codexStatusWindow = usage?.fiveHour ?? weekly
        codexStatusText = currentCodexStatusText()

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
        if window.hasExpired {
            showExpiredCodexRow(key: key)
            return
        }
        let limit = UsageLimit(
            utilization: window.usedPercent,
            resets_at: window.resetsAt.map { isoFormatter.string(from: $0) }
        )
        let windowSeconds = window.windowSeconds > 0 ? window.windowSeconds : defaultWindowSeconds
        updateUsageItem(key: key, limit: limit, windowSeconds: windowSeconds)
    }

    /// Scans local Codex sessions off the main thread, since the first scan of a busy week
    /// reads hundreds of megabytes; the row updates whenever the estimate lands.
    func refreshCodexOverage(_ usage: CodexUsage?) {
        guard codexTrackingEnabled, let usage else { return }
        lastCodexUsage = usage
        let period = codexOveragePeriod
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let estimate = estimateCodexOverage(usage: usage, period: period)
            DispatchQueue.main.async {
                guard let self, self.codexTrackingEnabled, self.codexAvailable else { return }
                // A scan started before the window setting changed would show the wrong period.
                guard period == self.codexOveragePeriod else { return }
                self.codexOverage = estimate
                self.updateCodexStatusDisplayMode()
                self.codexStatusText = self.currentCodexStatusText()
                self.updateCodexExtraItem()
                self.updateStatusItemTitle()
            }
        }
    }

    /// Same rule as Claude's Extra spend: the estimate takes the menu bar as soon as it grows, and
    /// hands it back once the session percentage moves again.
    private func updateCodexStatusDisplayMode() {
        let spent = codexOverage.flatMap { $0.credits > 0 ? $0.credits : nil }
        if let window = codexStatusWindow {
            codexStatusDisplayMode = StatusDisplayModeSelector.select(
                previous: codexStatusDisplayMode,
                fiveHourUtilization: window.usedPercent,
                previousFiveHourUtilization: previousCodexStatusUtilization,
                spentCredits: spent,
                previousSpentCredits: previousCodexOverageCredits
            )
            previousCodexStatusUtilization = window.usedPercent
        }
        previousCodexOverageCredits = spent
    }

    /// Like Claude, a spent window shows the estimated overage in dollars rather than its reset
    /// time, as does any window while the estimate is growing.
    func currentCodexStatusText() -> String? {
        guard let window = codexStatusWindow else { return nil }
        if window.hasExpired { return "--" }
        if let overage = codexOverage, overage.credits > 0,
            codexStatusDisplayMode == .overage || window.usedPercent >= 100
        {
            return CodexOverageCore.formatDollars(overage.dollars(pricePerCredit: codexCreditPrice))
        }
        return statusText(percent: window.usedPercent, resetsAt: window.resetsAt)
    }

    /// Shows the estimated spend past Codex's limits in the chosen period, hidden until there is
    /// some. Its submenu spells out the period and splits the spend by model.
    func updateCodexExtraItem() {
        guard let item = usageItems[codexExtraKey] else { return }
        guard let overage = codexOverage, overage.credits > 0 else {
            item.isHidden = true
            item.submenu = nil
            return
        }
        let label = categoryLabel(for: codexExtraKey)
        let dollars = CodexOverageCore.formatDollars(overage.dollars(pricePerCredit: codexCreditPrice))
        let suffix = overage.period.rowSuffix
        // Credits are OpenAI's billing unit; dollars alone read like Claude's Extra row.
        let detail = showCodexCredits ? "\(CodexOverageCore.formatCredits(overage.credits)) \(suffix)" : suffix
        item.title = "\(label): \(dollars) (\(detail))"
        item.attributedTitle = tabbedMenuItemString("\(label): \(dollars)", detail)
        item.submenu = codexOverageBreakdownMenu(overage)
        item.isHidden = false
    }

    private func codexOverageBreakdownMenu(_ overage: CodexOverageEstimate) -> NSMenu {
        let submenu = NSMenu()
        let periodText = CodexOverageCore.formatPeriod(overage)
        let period = NSMenuItem(title: periodText, action: nil, keyEquivalent: "")
        period.isEnabled = false
        period.attributedTitle = dimmedMenuItemString(periodText)
        submenu.addItem(period)
        submenu.addItem(NSMenuItem.separator())

        let font = NSFont.menuFont(ofSize: 14)
        let rows = overage.models.map { model in
            let dollars = CodexOverageCore.formatDollars(model.dollars(pricePerCredit: codexCreditPrice))
            let credits = CodexOverageCore.formatCredits(model.credits)
            let spend = showCodexCredits ? "\(dollars)  \(credits)" : dollars
            return (model: model.model, spend: spend, share: CodexOverageCore.formatShare(overage.tokenShare(of: model)))
        }
        // The token share sits right-aligned past the widest spend, so cost and usage read side by side.
        let widestSpend = rows.map { ($0.spend as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [
            NSTextTab(textAlignment: .left, location: 140, options: [:]),
            NSTextTab(textAlignment: .right, location: 140 + widestSpend + 64, options: [:]),
        ]

        var rowWidths = [period.attributedTitle?.size().width ?? 0]
        for row in rows {
            let title = "\(row.model): \(row.spend), \(row.share) of tokens"
            let item = NSMenuItem(title: title, action: #selector(noop), keyEquivalent: "")
            item.target = self
            let text = NSMutableAttributedString(
                string: "\(row.model)\t\(row.spend)\t",
                attributes: [.paragraphStyle: paragraph, .font: font, .foregroundColor: NSColor.labelColor])
            text.append(
                NSAttributedString(
                    string: row.share,
                    attributes: [.paragraphStyle: paragraph, .font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = text
            submenu.addItem(item)
            rowWidths.append(text.size().width)
        }

        submenu.addItem(NSMenuItem.separator())
        var footer = "\(overage.overageRequests) model requests past the limit"
        if overage.unpricedRequests > 0 {
            footer += ", \(overage.unpricedRequests) more on models without a published rate"
        }
        let info =
            "Estimated from the tokens Codex logged on this Mac for each model request sent while "
            + "a 5-hour or weekly limit was at 100%, during the period shown at the top "
            + "(Settings › Codex Extra Usage Window). The percentage is each model's share of those "
            + "tokens. Priced "
            + "with OpenAI's Codex credit rates at \(CodexOverageCore.formatPrice(codexCreditPrice)) per "
            + "credit (Settings › Codex Credit Price). Codex Cloud tasks and other devices are not included."
        submenu.addItem(infoFooterItem(footer, info: info, alignedTo: rowWidths.max() ?? 0))
        return submenu
    }

    /// A dimmed footer line ending in an ⓘ at the menu's trailing edge. Hovering the line shows
    /// `info`; the row stays a native menu item so its text lines up with the rows above it.
    private func infoFooterItem(_ text: String, info: String, alignedTo rowWidth: CGFloat) -> NSMenuItem {
        let font = NSFont.menuFont(ofSize: 14)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: max(rowWidth, textWidth + 32), options: [:])]
        let title = NSAttributedString(
            string: "\(text)\t\u{24D8}",
            attributes: [
                .paragraphStyle: paragraph,
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        // Enabled like the model rows, so the tooltip shows on hover.
        let item = NSMenuItem(title: text, action: #selector(noop), keyEquivalent: "")
        item.target = self
        item.attributedTitle = title
        item.toolTip = info
        return item
    }

    func updateCodexCreditPriceMenu() {
        var matchedPreset = false
        for item in codexCreditPriceItems {
            guard let price = item.representedObject as? Double else { continue }
            let isSelected = abs(price - codexCreditPrice) < 1e-9
            item.state = isSelected ? .on : .off
            matchedPreset = matchedPreset || isSelected
        }
        codexCreditPriceCustomItem?.state = matchedPreset ? .off : .on
        codexCreditPriceCustomItem?.title =
            matchedPreset ? "Custom…" : "Custom (\(CodexOverageCore.formatPrice(codexCreditPrice)))…"
    }

    @objc func toggleShowCodexCredits() {
        showCodexCredits = !showCodexCredits
    }

    func updateCodexOveragePeriodMenu() {
        for item in codexOveragePeriodItems {
            item.state = item.representedObject as? String == codexOveragePeriod.rawValue ? .on : .off
        }
    }

    @objc func selectCodexOveragePeriod(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let period = CodexOveragePeriod(rawValue: raw)
        else { return }
        codexOveragePeriod = period
    }

    @objc func selectCodexCreditPrice(_ sender: NSMenuItem) {
        guard let price = sender.representedObject as? Double else { return }
        codexCreditPrice = price
    }

    @objc func enterCustomCodexCreditPrice() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(.accessory) }

        let alert = NSAlert()
        alert.messageText = "Codex Credit Price"
        alert.informativeText =
            "Dollars per Codex credit, used to price the overage estimate. "
            + "OpenAI sells credits at $0.04 each (1,000 for $40); workspace pricing can differ."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = String(CodexOverageCore.formatPrice(codexCreditPrice).dropFirst())
        field.placeholderString = "0.04"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let price = CodexOverageCore.parsePricePerCredit(field.stringValue) else {
            let invalid = NSAlert()
            invalid.messageText = "Invalid price"
            invalid.informativeText = "Enter a dollar amount between 0 and 10, such as 0.04."
            invalid.runModal()
            return
        }
        codexCreditPrice = price
    }

    /// Dashes stand in for a rolled-over window so the last reading is not mistaken for a live one.
    private func showExpiredCodexRow(key: String) {
        guard let item = usageItems[key] else { return }
        let label = categoryLabel(for: key)
        item.title = "\(label): -- (resets ---)"
        item.attributedTitle = tabbedMenuItemString("\(label): --", "resets ---")
        rateItems[key]?.isHidden = true
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

    // MARK: - Opencode

    func updateOpencodeUI(_ usage: OpencodeUsage?) {
        let previous = opencodeUsage

        if opencodeTrackingEnabled, let usage, !usage.models.isEmpty {
            opencodeUsage = usage
            opencodeStatusText = OpencodeUsageCore.formatCost(usage.totalUSD)
        } else {
            opencodeUsage = nil
            opencodeStatusText = nil
        }

        // These rows are built from the fetched models rather than kept in `usageItems`,
        // so any change to what they'd say means rebuilding the menu.
        if menuReady && previous != opencodeUsage {
            rebuildMenu()
        }
    }

    // MARK: - Status Item

    func updateMenuBarOwnership(
        claudeUsage: UsageResponse?,
        codexUsage: CodexUsage?,
        cursorUsage: CursorUsage?,
        opencodeUsage: OpencodeUsage?
    ) {
        // Opencode reports dollars where the others report percentages. Both only ever climb
        // within a billing window, which is all the resolver compares, so the mixed units cost
        // nothing but tie-breaking precision between a big dollar jump and a big percent jump.
        menuBarOwnership = MenuBarOwnershipResolver.resolve(
            current: menuBarOwnership,
            utilizations: [
                .claude: claudeUsage?.five_hour?.utilization,
                .codex: codexTrackingEnabled
                    ? (codexUsage?.fiveHour ?? codexUsage?.weekly)?.usedPercent
                    : nil,
                .cursor: cursorTrackingEnabled ? cursorUsage?.highestPercent : nil,
                .opencode: opencodeTrackingEnabled ? opencodeUsage?.totalUSD : nil,
            ]
        )
        saveMenuBarOwnership()
    }

    func updateStatusItemTitle() {
        let statusTexts: [UsageProvider: String] = [
            .claude: claudeStatusText,
            .codex: codexStatusText,
            .cursor: cursorStatusText,
            .opencode: opencodeStatusText,
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

extension AppDelegate: WKNavigationDelegate {
    /// How short and how tall the breakdown panel is allowed to get once it is sized to its content.
    private static let breakdownMinimumHeight: CGFloat = 240
    private static let breakdownScreenMargin: CGFloat = 80

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Only the finished summary is measured; sizing to the placeholder would resize twice.
        guard navigation === breakdownNavigation, let panel = breakdownPanel else { return }
        webView.evaluateJavaScript("document.body.scrollHeight") { [weak self, weak panel] result, _ in
            guard let self, let panel, let measured = (result as? NSNumber)?.doubleValue else { return }
            self.resizeBreakdownPanel(panel, toContentHeight: CGFloat(measured))
        }
    }

    /// Fits the panel to the rendered page so no dead space is left under the heatmap, keeping the
    /// top edge where it is rather than re-centring a panel the user may already have moved.
    private func resizeBreakdownPanel(_ panel: NSPanel, toContentHeight height: CGFloat) {
        let available = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? height
        let capped = min(
            max(height, Self.breakdownMinimumHeight),
            max(available - Self.breakdownScreenMargin, Self.breakdownMinimumHeight)
        )
        let contentWidth = panel.contentView?.bounds.width ?? panel.frame.width
        var frame = panel.frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentWidth, height: capped))
        guard abs(frame.height - panel.frame.height) > 1 else { return }
        frame.origin = NSPoint(x: panel.frame.minX, y: panel.frame.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }
}
