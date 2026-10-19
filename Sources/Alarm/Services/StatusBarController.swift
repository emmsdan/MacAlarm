import AppKit
import SwiftUI

@MainActor
public final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    
    public override init() {
        super.init()
        setupStatusItem()
        startTimer()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: "Real Alarm")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
        buildMenu()
    }
    
    private func startTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.buildMenu()
            }
        }
    }
    
    private func buildMenu() {
        let menu = NSMenu()
        
        // Status header
        let store = AlarmStore.shared
        let summaryItem = NSMenuItem(title: store.nextUpcomingSummary, action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open Dashboard
        let openItem = NSMenuItem(title: "Open Real Alarm", action: #selector(openDashboard), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit Real Alarm", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func statusBarButtonClicked() {
        statusItem?.button?.performClick(nil)
    }
    
    @objc private func openDashboard() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title.contains("Alarm") && !(window is FullScreenAlarmWindow) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // If closed, trigger window open
        if let first = NSApp.windows.first(where: { !($0 is FullScreenAlarmWindow) }) {
            first.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
