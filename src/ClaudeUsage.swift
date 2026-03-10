import Cocoa
import Carbon.HIToolbox
import ServiceManagement
import WebKit

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
    var rateItems: [String: NSMenuItem] = [:]
    var updatedItem: NSMenuItem!
    var rateLimitItem: NSMenuItem!
    var isRateLimited = false

    // Usage graph
    var graphPanel: NSPanel?

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

    // Rate insight toggle
    var rateInsightEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(rateInsightEnabled, forKey: "rateInsightEnabled")
            rateInsightItem?.state = rateInsightEnabled ? .on : .off
            for (_, item) in rateItems { item.isHidden = !rateInsightEnabled }
        }
    }
    var rateInsightItem: NSMenuItem!

    // Open at login toggle
    var openAtLoginEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(openAtLoginEnabled, forKey: "openAtLoginEnabled")
            openAtLoginItem?.state = openAtLoginEnabled ? .on : .off
            updateLoginItem()
        }
    }
    var openAtLoginItem: NSMenuItem!

    // Usage source: 0 = Desktop cookies (default), 1 = OAuth API
    var usageSource: Int = 0 {
        didSet {
            UserDefaults.standard.set(usageSource, forKey: "usageSource")
            updateUsageSourceMenu()
        }
    }
    var usageSourceCookiesItem: NSMenuItem!
    var usageSourceOAuthItem: NSMenuItem!

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

    // Local key monitor for menu shortcuts (x, c, r) when menu is open
    var menuKeyMonitor: Any?

    // Global hotkey
    var hotKeyRef: EventHotKeyRef?
    var eventHandlerRef: EventHandlerRef?
    var lastMenuCloseTime: Date = .distantPast
    var hotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_X) // default: X (Cmd+Shift+X)
    var hotkeyModifiers: UInt32 = UInt32(cmdKey | shiftKey) // default: Cmd+Shift
    var hotkeyCurrentItem: NSMenuItem!
    var hotkeyRecordItem: NSMenuItem!
    var hotkeyRemoveItem: NSMenuItem!

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

        // Migrate usage history from UserDefaults to persistent file
        migrateUserDefaultsHistory()

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
        if ud.object(forKey: "rateInsightEnabled") != nil {
            rateInsightEnabled = ud.bool(forKey: "rateInsightEnabled")
        }
        if ud.object(forKey: "openAtLoginEnabled") != nil {
            openAtLoginEnabled = ud.bool(forKey: "openAtLoginEnabled")
        }
        if ud.object(forKey: "usageSource") != nil {
            usageSource = ud.integer(forKey: "usageSource")
        } else {
            usageSource = 0 // default: Desktop cookies
        }

        if let saved = ud.object(forKey: "pinnedKeys") as? [String] {
            pinnedKeys = Set(saved)
        }

        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "..."

        // Create usage menu items and rate sub-items for all categories
        for key in allCategoryKeys {
            let label = categoryLabels[key] ?? key
            let item = NSMenuItem(title: "\(label): ...", action: #selector(noop), keyEquivalent: "")
            item.target = self
            usageItems[key] = item

            let rateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            rateItem.isEnabled = false
            rateItem.isHidden = true
            rateItems[key] = rateItem
        }
        updatedItem = NSMenuItem(title: "Updated: --", action: nil, keyEquivalent: "")
        rateLimitItem = NSMenuItem(title: "Rate limited. Try again later.", action: nil, keyEquivalent: "")
        rateLimitItem.isEnabled = false

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
        updateUsageSourceMenu()

        // Initial fetch
        refresh()

        // Start timer
        restartTimer()

        // Load saved hotkey
        if ud.object(forKey: "hotkeyKeyCode") != nil {
            hotkeyKeyCode = UInt32(ud.integer(forKey: "hotkeyKeyCode"))
            hotkeyModifiers = UInt32(ud.integer(forKey: "hotkeyModifiers"))
        }

        // Register global hotkey
        installHotkeyHandler()
        if hotkeyKeyCode != UInt32.max {
            registerGlobalHotkey()
        }

        // Subscribe to sleep/wake notifications
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleSleep), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(handleWake), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    // MARK: - Global Hotkey

    func installHotkeyHandler() {
        var eventType = EventTypeSpec(eventClass: UInt32(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            let app = NSApplication.shared.delegate as! AppDelegate
            if Date().timeIntervalSince(app.lastMenuCloseTime) > 0.5 {
                app.showMenu()
            }
            return noErr
        }, 1, &eventType, nil, &eventHandlerRef)
    }

    func registerGlobalHotkey() {
        unregisterGlobalHotkey()
        guard hotkeyKeyCode != UInt32.max else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5553), id: 1)
        RegisterEventHotKey(hotkeyKeyCode, hotkeyModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        updateHotkeyMenu()
    }

    func unregisterGlobalHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    func saveHotkeyPrefs() {
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(hotkeyModifiers), forKey: "hotkeyModifiers")
    }

    func updateHotkeyMenu() {
        if hotkeyKeyCode == UInt32.max {
            hotkeyCurrentItem?.title = "Current: None"
            hotkeyRemoveItem?.isEnabled = false
        } else {
            hotkeyCurrentItem?.title = "Current: \(hotkeyDisplayString())"
            hotkeyRemoveItem?.isEnabled = true
        }
    }

    func hotkeyDisplayString() -> String {
        guard hotkeyKeyCode != UInt32.max else { return "None" }
        var parts: [String] = []
        if hotkeyModifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        if hotkeyModifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if hotkeyModifiers & UInt32(optionKey) != 0 { parts.append("Opt") }
        if hotkeyModifiers & UInt32(controlKey) != 0 { parts.append("Ctrl") }
        parts.append(keyCodeToString(hotkeyKeyCode))
        return parts.joined(separator: "+")
    }

    func keyCodeToString(_ keyCode: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Esc",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Grave): "`",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    /// Convert NSEvent modifier flags to Carbon modifier mask
    func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    func menuWillOpen(_ menu: NSMenu) {
        installMenuKeyMonitor()
    }

    func menuDidClose(_ menu: NSMenu) {
        uninstallMenuKeyMonitor()
        lastMenuCloseTime = Date()
        if !hasData {
            statusItem.button?.title = "..."
        }
    }

    func installMenuKeyMonitor() {
        uninstallMenuKeyMonitor()
        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.isEmpty else { return event }
            switch event.keyCode {
            case UInt16(kVK_ANSI_X):
                self.closeMenu()
                return nil
            case UInt16(kVK_ANSI_C):
                self.copyUsage()
                return nil
            case UInt16(kVK_ANSI_R):
                self.refresh()
                return nil
            default:
                return event
            }
        }
    }

    func uninstallMenuKeyMonitor() {
        if let monitor = menuKeyMonitor {
            NSEvent.removeMonitor(monitor)
            menuKeyMonitor = nil
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
        button.performClick(nil)
    }

    // MARK: - Menu Building

}

