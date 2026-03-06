import Cocoa
import Carbon.HIToolbox

// MARK: - Constants

let appVersion = "2.1.34"

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let isoFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "h:mm:ss a"
    f.timeZone = TimeZone(identifier: "America/New_York")
    return f
}()

private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

// MARK: - Usage API

struct UsageResponse: Codable {
    let five_hour: UsageLimit?
    let seven_day: UsageLimit?
    let seven_day_opus: UsageLimit?
    let seven_day_sonnet: UsageLimit?
    let seven_day_oauth_apps: UsageLimit?
    let seven_day_cowork: UsageLimit?
    let extra_usage: ExtraUsage?
}

func detectModel(_ usage: UsageResponse) -> String {
    if let opus = usage.seven_day_opus, opus.utilization > 0 { return "opus" }
    if let sonnet = usage.seven_day_sonnet, sonnet.utilization > 0 { return "sonnet" }
    return "opus"
}

struct UsageLimit: Codable {
    let utilization: Double
    let resets_at: String?
}

struct ExtraUsage: Codable {
    let is_enabled: Bool
    let monthly_limit: Double?
    let used_credits: Double?
    let utilization: Double?
}

// All trackable usage categories
let allCategoryKeys: [String] = [
    "five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet",
    "seven_day_oauth_apps", "seven_day_cowork", "extra_usage"
]
let categoryLabels: [String: String] = [
    "five_hour": "5-hour",
    "seven_day": "Weekly",
    "seven_day_opus": "Opus",
    "seven_day_sonnet": "Sonnet",
    "seven_day_oauth_apps": "OAuth Apps",
    "seven_day_cowork": "Cowork",
    "extra_usage": "Extra"
]
let defaultPinnedKeys: Set<String> = ["five_hour", "seven_day", "seven_day_sonnet", "extra_usage"]

func getOAuthToken() -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    task.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let jsonData = json.data(using: .utf8),
              let creds = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = creds["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else {
            return nil
        }
        return token
    } catch {
        return nil
    }
}

func fetchUsage(token: String, completion: @escaping (UsageResponse?) -> Void) {
    guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
        completion(nil)
        return
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue("claude-code/\(appVersion)", forHTTPHeaderField: "User-Agent")

    let session = URLSession(configuration: .ephemeral)
    session.dataTask(with: request) { data, _, _ in
        guard let data = data,
              let usage = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            completion(nil)
            return
        }
        completion(usage)
    }.resume()
}

func formatReset(_ isoString: String) -> String {
    if let date = isoFormatter.date(from: isoString) {
        return formatResetDate(date)
    }
    if let date = isoFormatterNoFrac.date(from: isoString) {
        return formatResetDate(date)
    }
    return "?"
}

func formatResetDate(_ date: Date) -> String {
    let diff = date.timeIntervalSince(Date())
    if diff < 0 { return "now" }

    let hours = Int(diff) / 3600
    let mins = (Int(diff) % 3600) / 60

    if hours == 0 {
        return "\(mins)m"
    } else if hours < 24 {
        return "\(hours)h \(mins)m"
    } else {
        return dateFormatter.string(from: date)
    }
}

// MARK: - Sound Playback

func playClicks(count: Int, soundName: String, delay: TimeInterval = 0.15, completion: (() -> Void)? = nil) {
    guard count > 0 else {
        completion?()
        return
    }
    if let sound = NSSound(named: NSSound.Name(soundName)) {
        sound.play()
    }
    if count > 1 {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            playClicks(count: count - 1, soundName: soundName, delay: delay, completion: completion)
        }
    } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completion?()
        }
    }
}

func playAlarmBursts(bursts: Int = 3, clicksPerBurst: Int = 5, soundName: String, checkMuted: @escaping () -> Bool, completion: (() -> Void)? = nil) {
    guard bursts > 0 else {
        completion?()
        return
    }
    if checkMuted() {
        completion?()
        return
    }
    playClicks(count: clicksPerBurst, soundName: soundName) {
        if bursts > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playAlarmBursts(bursts: bursts - 1, clicksPerBurst: clicksPerBurst, soundName: soundName, checkMuted: checkMuted, completion: completion)
            }
        } else {
            completion?()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var timer: Timer?

    // Store state
    var currentPct: String = "..."
    var hasData = false

    // Data-driven usage items: key -> menu item
    var usageItems: [String: NSMenuItem] = [:]
    var updatedItem: NSMenuItem!

    // Which keys are pinned to the main menu
    var menuReady = false
    var suppressRebuild = false
    var needsMenuRebuild = false
    var pinnedKeys: Set<String> = defaultPinnedKeys {
        didSet {
            UserDefaults.standard.set(Array(pinnedKeys), forKey: "pinnedKeys")
            if menuReady && !suppressRebuild { rebuildMenu() }
        }
    }

    // More submenu items for toggling
    var moreToggleItems: [String: NSMenuItem] = [:]
    var moreMenu: NSMenu!

    // Refresh interval items
    var interval1mItem: NSMenuItem!
    var interval5mItem: NSMenuItem!
    var interval30mItem: NSMenuItem!
    var interval1hItem: NSMenuItem!

    // Notification menu items
    var alert100Item: NSMenuItem!
    var alertLimitItem: NSMenuItem!
    var alarmAfter100Item: NSMenuItem!
    var alarmAfterUsedItem: NSMenuItem!
    var alarmAfterAnyItem: NSMenuItem!
    var alarmOffItem: NSMenuItem!
    var alarmSkipItem: NSMenuItem!

    // Sound menu items
    var soundItems: [NSMenuItem] = []

    // Colors toggle
    var colorsEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(colorsEnabled, forKey: "colorsEnabled")
            colorsItem?.state = colorsEnabled ? .on : .off
        }
    }
    var colorsItem: NSMenuItem!

    // Current interval in seconds
    var refreshInterval: TimeInterval = 300 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
            updateIntervalMenu()
            restartTimer()
        }
    }

    // Notification preferences
    var alert100Enabled: Bool = true {
        didSet { UserDefaults.standard.set(alert100Enabled, forKey: "alert100Enabled") }
    }
    var alertLimitEnabled: Bool = true {
        didSet { UserDefaults.standard.set(alertLimitEnabled, forKey: "alertLimitEnabled") }
    }
    // 0=Off, 1=After 100%, 2=After any used, 3=After any session
    var alarmCondition: Int = 0 {
        didSet {
            UserDefaults.standard.set(alarmCondition, forKey: "alarmCondition")
            updateAlarmMenu()
        }
    }
    var alarmSkipIfPrevZero: Bool = false {
        didSet { UserDefaults.standard.set(alarmSkipIfPrevZero, forKey: "alarmSkipIfPrevZero") }
    }
    var selectedSoundName: String = "Tink" {
        didSet {
            UserDefaults.standard.set(selectedSoundName, forKey: "selectedSoundName")
            updateSoundMenu()
        }
    }

    // Global hotkey
    var hotKeyRef: EventHotKeyRef?
    var lastMenuCloseTime: Date = .distantPast

    // Transition tracking
    var previousFiveHourUtil: Double = -1
    var previousExtraUtil: Double = -1
    var lastKnownResetDate: Date?
    var lastSessionFinalUtil: Double = 0
    var previousSessionHadUsage: Bool = false
    var alarmIsPlaying: Bool = false
    var alarmCheckTimer: Timer?
    var lastFetchDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Load saved preferences
        let ud = UserDefaults.standard
        let savedInterval = ud.double(forKey: "refreshInterval")
        if savedInterval > 0 { refreshInterval = savedInterval }

        if ud.object(forKey: "alert100Enabled") != nil {
            alert100Enabled = ud.object(forKey: "alert100Enabled") as? Bool ?? true
        }
        if ud.object(forKey: "alertLimitEnabled") != nil {
            alertLimitEnabled = ud.object(forKey: "alertLimitEnabled") as? Bool ?? true
        }
        alarmCondition = ud.object(forKey: "alarmCondition") as? Int ?? 0
        if ud.object(forKey: "alarmSkipIfPrevZero") != nil {
            alarmSkipIfPrevZero = ud.object(forKey: "alarmSkipIfPrevZero") as? Bool ?? false
        }
        selectedSoundName = ud.object(forKey: "selectedSoundName") as? String ?? "Tink"
        if ud.object(forKey: "colorsEnabled") != nil {
            colorsEnabled = ud.bool(forKey: "colorsEnabled")
        }

        if let saved = ud.object(forKey: "pinnedKeys") as? [String] {
            pinnedKeys = Set(saved)
        }

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: 0)
        statusItem.button?.title = ""

        // Create usage menu items for all categories
        for key in allCategoryKeys {
            let label = categoryLabels[key] ?? key
            let item = NSMenuItem(title: "\(label): ...", action: #selector(noop), keyEquivalent: "")
            item.target = self
            usageItems[key] = item
        }
        updatedItem = NSMenuItem(title: "Updated: --", action: nil, keyEquivalent: "")

        // Build the full menu
        menu = NSMenu()
        menu.delegate = self
        buildMenu()
        menuReady = true

        // Set menu directly for proper display
        statusItem.menu = menu

        // Update checkmarks
        updateIntervalMenu()
        updateNotificationMenu()
        updateAlarmMenu()
        updateSoundMenu()

        // Initial fetch
        refresh()

        // Start timer
        restartTimer()

        // Register global hotkey: Cmd+Shift+C via Carbon
        registerGlobalHotkey()

        // Subscribe to sleep/wake notifications
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleSleep), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleWake), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    // MARK: - Global Hotkey

    func registerGlobalHotkey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5553), id: 1) // "CLUS"
        var eventType = EventTypeSpec(eventClass: UInt32(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            let app = NSApplication.shared.delegate as! AppDelegate
            // Ignore queued hotkey events that fired while menu was open
            if Date().timeIntervalSince(app.lastMenuCloseTime) > 0.5 {
                app.showMenu()
            }
            return noErr
        }, 1, &eventType, nil, nil)

        guard status == noErr else { return }

        // Cmd+Shift+C: kVK_ANSI_C = 8, cmdKey | shiftKey
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_C), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func menuDidClose(_ menu: NSMenu) {
        lastMenuCloseTime = Date()
        if !hasData {
            statusItem.length = 0
            statusItem.button?.title = ""
        }
    }

    @objc func noop() {}

    @objc func closeMenu() {
        menu.cancelTracking()
    }

    func showMenu() {
        guard let button = statusItem.button else { return }
        if needsMenuRebuild {
            rebuildMenu()
            needsMenuRebuild = false
        }
        // Temporarily make visible if hidden so the menu can anchor
        if statusItem.length == 0 {
            statusItem.length = NSStatusItem.variableLength
            button.title = hasData ? currentPct : "..."
        }
        button.performClick(nil)
    }

    // MARK: - Menu Building

    func buildMenu() {
        menu.removeAllItems()

        // Pinned usage items (in canonical order)
        for key in allCategoryKeys {
            if pinnedKeys.contains(key), let item = usageItems[key] {
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(updatedItem)

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

        helpMenu.addItem(NSMenuItem.separator())

        let shareItem = NSMenuItem(title: "Share...", action: #selector(shareApp), keyEquivalent: "")
        shareItem.target = self
        helpMenu.addItem(shareItem)

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
        // Re-render with colors by triggering a refresh
        refresh()
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

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Refresh & Update

    @objc func refresh() {
        if !hasData {
            statusItem.length = 0
            statusItem.button?.title = ""
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let token = getOAuthToken() else {
                DispatchQueue.main.async {
                    self?.hasData = false
                    self?.statusItem.length = 0
                    self?.statusItem.button?.title = ""
                }
                return
            }

            fetchUsage(token: token) { usage in
                DispatchQueue.main.async {
                    self?.updateUI(usage: usage)
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
            .foregroundColor: color ?? NSColor.labelColor
        ])
    }

    /// Calculate a green→yellow→red color based on usage pace.
    /// ratio = usage% / time_elapsed%, where 1.0 means perfectly on track.
    func severityColor(utilization: Double, resetsAt: String?, windowSeconds: TimeInterval) -> NSColor? {
        guard colorsEnabled, utilization > 0 else { return nil }
        if utilization >= 100 { return NSColor(calibratedHue: 0, saturation: 0.8, brightness: 1.0, alpha: 1.0) }

        guard let resetStr = resetsAt,
              let resetDate = isoFormatter.date(from: resetStr) ?? isoFormatterNoFrac.date(from: resetStr) else {
            return nil
        }

        let remaining = max(resetDate.timeIntervalSince(Date()), 0)
        let elapsed = windowSeconds - remaining
        let elapsedPct = max(elapsed / windowSeconds * 100, 1)
        let ratio = utilization / elapsedPct

        // ratio <= 0.8: green, 0.8-1.5: green→yellow, 1.5-2.5: yellow→red, >= 2.5: red
        let hue: CGFloat
        if ratio <= 0.8 {
            hue = 120.0 / 360.0 // green
        } else if ratio <= 1.5 {
            // green (120°) → yellow (50°)
            let t = CGFloat((ratio - 0.8) / 0.7)
            hue = (120.0 - t * 70.0) / 360.0
        } else if ratio <= 2.5 {
            // yellow (50°) → red (0°)
            let t = CGFloat((ratio - 1.5) / 1.0)
            hue = (50.0 - t * 50.0) / 360.0
        } else {
            hue = 0 // red
        }
        return NSColor(calibratedHue: hue, saturation: 0.8, brightness: 1.0, alpha: 1.0)
    }

    func dimmedMenuItemString(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 14),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    func updateUsageItem(key: String, limit: UsageLimit?, windowSeconds: TimeInterval = 0) {
        guard let item = usageItems[key] else { return }
        let label = categoryLabels[key] ?? key
        if let l = limit {
            let pct = Int(l.utilization)
            let reset = l.resets_at.map { formatReset($0) } ?? "--"
            item.title = "\(label): \(pct)% (resets \(reset))"
            let color = windowSeconds > 0
                ? severityColor(utilization: l.utilization, resetsAt: l.resets_at, windowSeconds: windowSeconds)
                : nil
            item.attributedTitle = tabbedMenuItemString("\(label): \(pct)%", "resets \(reset)", color: color)
        } else {
            item.title = "\(label): --"
            item.attributedTitle = nil
        }
    }

    func updateUI(usage: UsageResponse?) {
        guard let usage = usage else {
            hasData = false
            statusItem.length = 0
            statusItem.button?.title = ""
            return
        }

        lastFetchDate = Date()

        // Update all limit-based categories
        updateUsageItem(key: "five_hour", limit: usage.five_hour, windowSeconds: 5 * 3600)
        updateUsageItem(key: "seven_day", limit: usage.seven_day, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_opus", limit: usage.seven_day_opus, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_sonnet", limit: usage.seven_day_sonnet, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_oauth_apps", limit: usage.seven_day_oauth_apps, windowSeconds: 7 * 86400)
        updateUsageItem(key: "seven_day_cowork", limit: usage.seven_day_cowork, windowSeconds: 7 * 86400)

        // Extra usage (special format)
        if let e = usage.extra_usage, e.is_enabled,
           let used = e.used_credits, let limit = e.monthly_limit, let util = e.utilization {
            let extraText = String(format: "Extra: $%.2f/$%.0f", used / 100, limit / 100)
            let extraDetail = String(format: "%.0f%%", util)
            usageItems["extra_usage"]?.title = String(format: "Extra: $%.2f/$%.0f (%.0f%%)", used / 100, limit / 100, util)
            usageItems["extra_usage"]?.attributedTitle = tabbedMenuItemString(extraText, extraDetail)
        } else {
            usageItems["extra_usage"]?.title = "Extra: --"
            usageItems["extra_usage"]?.attributedTitle = nil
        }

        // 5-hour specific: reset date, transitions, menu bar title
        if let h = usage.five_hour {
            let pct = Int(h.utilization)
            let reset = h.resets_at.map { formatReset($0) } ?? "--"

            if let resetStr = h.resets_at {
                let parsedDate = isoFormatter.date(from: resetStr) ?? isoFormatterNoFrac.date(from: resetStr)

                if let newResetDate = parsedDate {
                    if let lastReset = lastKnownResetDate,
                       abs(newResetDate.timeIntervalSince(lastReset)) > 60 {
                        triggerAlarmIfNeeded(endedSessionUtil: lastSessionFinalUtil)
                    }
                    lastKnownResetDate = newResetDate
                    scheduleAlarmCheckTimer(for: newResetDate)
                }
            }

            let newUtil = h.utilization
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
                if let e = usage.extra_usage, e.is_enabled, let spent = e.used_credits {
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

        // Extra usage transition detection
        if let e = usage.extra_usage, let util = e.utilization {
            if previousExtraUtil >= 0 && previousExtraUtil < 100 && util >= 100 {
                if alertLimitEnabled {
                    playClicks(count: 3, soundName: selectedSoundName)
                }
            }
            previousExtraUtil = util
        }

        // Updated time
        let stale = isDataStale() ? " (stale)" : ""
        let updatedText = "Updated: \(timeFormatter.string(from: Date()))\(stale)"
        updatedItem.title = updatedText
        updatedItem.attributedTitle = dimmedMenuItemString(updatedText)
    }

    func isDataStale() -> Bool {
        guard let last = lastFetchDate else { return false }
        return Date().timeIntervalSince(last) > refreshInterval * 2
    }

    // MARK: - Alarm Logic

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

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
