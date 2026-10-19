import Foundation
import AppKit
import SwiftUI

final class FullScreenAlarmWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    // Intercept escape to prevent standard system dismiss without completing challenge
    override func cancelOperation(_ sender: Any?) {
        // Do nothing on Esc - force user to use dismiss/snooze controls
    }
}

@MainActor
public final class FullScreenAlarmManager: ObservableObject {
    public static let shared = FullScreenAlarmManager()
    
    @Published public private(set) var isPresented: Bool = false
    private var windows: [NSWindow] = []
    private var focusTimer: Timer?
    
    private init() {}
    
    public func showFullScreen(for alarm: AlarmItem) {
        dismiss() // Clean up any existing windows
        
        isPresented = true
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        
        let primaryScreen = NSScreen.main ?? screens[0]
        
        for screen in screens {
            let isPrimary = (screen == primaryScreen)
            let window = FullScreenAlarmWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            
            // Shielding level is above dock, menu bar, and regular windows
            window.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.title = "ALARM: \(alarm.title)"
            
            if isPrimary {
                let contentView = FullScreenAlarmView(alarm: alarm)
                let hostingView = NSHostingView(rootView: contentView)
                window.contentView = hostingView
                window.setFrame(screen.frame, display: true)
                window.makeKeyAndOrderFront(nil)
            } else {
                // Secondary display blackout screen
                let secondaryView = FullScreenSecondaryView(alarm: alarm)
                let hostingView = NSHostingView(rootView: secondaryView)
                window.contentView = hostingView
                window.setFrame(screen.frame, display: true)
                window.orderFront(nil)
            }
            
            windows.append(window)
        }
        
        // Bring app and primary window to absolute front
        NSApp.activate(ignoringOtherApps: true)
        if let primary = windows.first {
            primary.makeKeyAndOrderFront(nil)
        }
        
        // Assert focus periodically while ringing so user is not distracted
        focusTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPresented else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    public func dismiss() {
        focusTimer?.invalidate()
        focusTimer = nil
        
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        isPresented = false
    }
}
