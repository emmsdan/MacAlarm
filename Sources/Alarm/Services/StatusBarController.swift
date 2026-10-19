import AppKit
import SwiftUI
import Combine

@MainActor
public final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    public override init() {
        super.init()
        setupStatusItem()
        setupSubscriptions()
        startTimer()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: "MacAlarm Now")
        }
        buildMenu()
    }
    
    private func setupSubscriptions() {
        AlarmStore.shared.$alarms
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
            
        AlarmStore.shared.$currentlyRingingAlarm
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ringing in
                self?.updateStatusIcon(isRinging: ringing != nil)
                self?.buildMenu()
            }
            .store(in: &cancellables)
            
        RedisSyncService.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
            
        RedisSyncService.shared.$lastSyncDate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
            
        RedisSyncService.shared.$isSyncing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusIcon(isRinging: Bool) {
        if isRinging {
            statusItem?.button?.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Alarm Ringing!")
        } else {
            statusItem?.button?.image = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: "MacAlarm Now")
        }
    }
    
    private func startTimer() {
        // Heartbeat to keep countdown strings fresh
        updateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.buildMenu()
            }
        }
    }
    
    // MARK: - NSMenuDelegate
    
    public func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
        // Trigger a background pull whenever the user opens the menu
        if RedisSyncService.shared.settings.isEnabled {
            RedisSyncService.shared.pullLatestFromRedis()
        }
    }
    
    // MARK: - Menu Construction
    
    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        
        let store = AlarmStore.shared
        let sync = RedisSyncService.shared
        
        // 1. If currently ringing, show urgent banner
        if let ringing = store.currentlyRingingAlarm {
            let ringingItem = NSMenuItem(
                title: "🚨 RINGING: \(ringing.title) - Click to Dismiss",
                action: #selector(dismissRingingAlarm),
                keyEquivalent: ""
            )
            ringingItem.target = self
            ringingItem.image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)
            menu.addItem(ringingItem)
            
            let snoozeItem = NSMenuItem(
                title: "💤 Snooze Alarm (\(ringing.snoozeMinutes) min)",
                action: #selector(snoozeRingingAlarm),
                keyEquivalent: ""
            )
            snoozeItem.target = self
            menu.addItem(snoozeItem)
            
            menu.addItem(NSMenuItem.separator())
        }
        
        // 2. Next Upcoming Summary Header
        let summaryItem = NSMenuItem(title: store.nextUpcomingSummary, action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        if let icon = NSImage(systemSymbolName: "clock.badge.checkmark", accessibilityDescription: nil) {
            summaryItem.image = icon
        }
        menu.addItem(summaryItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Dynamic Alarms List
        let alarmsHeader = NSMenuItem(title: "ALARMS (\(store.alarms.count))", action: nil, keyEquivalent: "")
        alarmsHeader.isEnabled = false
        menu.addItem(alarmsHeader)
        
        if store.alarms.isEmpty {
            let emptyItem = NSMenuItem(title: "No Alarms Scheduled", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for alarm in store.alarms {
                let item = makeAlarmMenuItem(for: alarm)
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Quick Actions
        let newItem = NSMenuItem(title: "New Alarm...", action: #selector(newAlarmClicked), keyEquivalent: "n")
        newItem.target = self
        if let plusImg = NSImage(systemSymbolName: "plus", accessibilityDescription: nil) {
            newItem.image = plusImg
        }
        menu.addItem(newItem)
        
        // Cloud Sync Info Line
        let syncStatusItem = NSMenuItem(
            title: "Cloud: \(sync.status.rawValue)",
            action: nil,
            keyEquivalent: ""
        )
        syncStatusItem.isEnabled = false
        if let syncImg = NSImage(systemSymbolName: sync.status.iconName, accessibilityDescription: nil) {
            syncStatusItem.image = syncImg
        }
        menu.addItem(syncStatusItem)
        
        let syncNowTitle = sync.isSyncing ? "Syncing with Cloud..." : "Sync Now"
        let syncNowItem = NSMenuItem(
            title: syncNowTitle,
            action: #selector(syncNowClicked),
            keyEquivalent: "r"
        )
        syncNowItem.target = self
        if let syncIcon = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil) {
            syncNowItem.image = syncIcon
        }
        syncNowItem.isEnabled = !sync.isSyncing && sync.settings.isEnabled
        menu.addItem(syncNowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 5. Open & Quit
        let openItem = NSMenuItem(title: "Open MacAlarm Now", action: #selector(openDashboard), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        
        let quitItem = NSMenuItem(title: "Quit MacAlarm Now", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    private func makeAlarmMenuItem(for alarm: AlarmItem) -> NSMenuItem {
        var title = "\(alarm.formattedTime)  \(alarm.title)"
        if alarm.isSnoozed, let snoozeUntil = alarm.snoozeUntil {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            title += " [Snoozed: \(formatter.string(from: snoozeUntil))]"
        } else if !alarm.repeatDays.isEmpty {
            title += " (\(alarm.repeatDaysSummary))"
        } else {
            title += " (Once)"
        }
        
        let item = NSMenuItem(title: title, action: #selector(toggleAlarmClicked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = alarm.id
        item.state = alarm.isEnabled ? .on : .off
        item.image = NSImage(systemSymbolName: alarm.soundType.iconName, accessibilityDescription: nil)
        item.toolTip = "Click to turn \(alarm.isEnabled ? "off" : "on")"
        
        // Submenu for alarm details and quick management
        let submenu = NSMenu()
        
        let toggleSubItem = NSMenuItem(
            title: alarm.isEnabled ? "Disable Alarm" : "Enable Alarm",
            action: #selector(toggleAlarmClicked(_:)),
            keyEquivalent: ""
        )
        toggleSubItem.target = self
        toggleSubItem.representedObject = alarm.id
        submenu.addItem(toggleSubItem)
        
        let editSubItem = NSMenuItem(
            title: "Edit in MacAlarm...",
            action: #selector(editAlarmClicked(_:)),
            keyEquivalent: ""
        )
        editSubItem.target = self
        editSubItem.representedObject = alarm.id
        submenu.addItem(editSubItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        let repeatItem = NSMenuItem(title: "Repeat: \(alarm.repeatDaysSummary)", action: nil, keyEquivalent: "")
        repeatItem.isEnabled = false
        submenu.addItem(repeatItem)
        
        let soundItem = NSMenuItem(title: "Sound: \(alarm.soundType.displayName)", action: nil, keyEquivalent: "")
        soundItem.isEnabled = false
        submenu.addItem(soundItem)
        
        let challengeItem = NSMenuItem(title: "Challenge: \(alarm.challengeType.displayName)", action: nil, keyEquivalent: "")
        challengeItem.isEnabled = false
        submenu.addItem(challengeItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        let deleteSubItem = NSMenuItem(
            title: "Delete Alarm",
            action: #selector(deleteAlarmClicked(_:)),
            keyEquivalent: ""
        )
        deleteSubItem.target = self
        deleteSubItem.representedObject = alarm.id
        submenu.addItem(deleteSubItem)
        
        item.submenu = submenu
        return item
    }
    
    // MARK: - Actions
    
    @objc private func toggleAlarmClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        AlarmStore.shared.toggleAlarm(id: id)
    }
    
    @objc private func editAlarmClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        openDashboard()
        NotificationCenter.default.post(name: .openEditAlarmSheet, object: id)
    }
    
    @objc private func deleteAlarmClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        AlarmStore.shared.deleteAlarm(id: id)
    }
    
    @objc private func newAlarmClicked() {
        openDashboard()
        NotificationCenter.default.post(name: .openNewAlarmSheet, object: nil)
    }
    
    @objc private func syncNowClicked() {
        RedisSyncService.shared.syncNow()
    }
    
    @objc private func dismissRingingAlarm() {
        AlarmStore.shared.dismissCurrentlyRinging()
    }
    
    @objc private func snoozeRingingAlarm() {
        AlarmStore.shared.snoozeCurrentlyRinging()
    }
    
    @objc private func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where !(window is FullScreenAlarmWindow) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let first = NSApp.windows.first(where: { !($0 is FullScreenAlarmWindow) }) {
            first.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
