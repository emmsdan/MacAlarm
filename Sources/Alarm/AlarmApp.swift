import SwiftUI

@main
struct AlarmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Window("Mac Real Alarm", id: "main") {
            MainDashboardView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 820, height: 700)
    }
}
