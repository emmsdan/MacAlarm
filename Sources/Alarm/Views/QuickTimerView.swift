import SwiftUI

public struct QuickTimerView: View {
    @ObservedObject private var store = AlarmStore.shared
    
    private let presets: [(title: String, desc: String, minutes: Int, icon: String)] = [
        ("Quick Test (1m)", "Test alarm ringing and singing loud!", 1, "bolt.fill"),
        ("Power Nap (20m)", "Quick recharge power nap to boost energy!", 20, "bed.double.fill"),
        ("Pomodoro Focus (25m)", "Time for a 5-minute break and eye rest!", 25, "timer"),
        ("Deep Work (45m)", "Sprint complete! Stand up, stretch, and hydrate!", 45, "brain.head.profile"),
    ]
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.orange)
                Text("Quick Timers & Power Naps")
                    .font(.headline)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(presets, id: \.title) { preset in
                    Button(action: {
                        startQuickAlarm(preset: preset)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: preset.icon)
                                .font(.title3)
                                .foregroundColor(.orange)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(preset.desc)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.windowBackgroundColor))
        )
    }
    
    private func startQuickAlarm(preset: (title: String, desc: String, minutes: Int, icon: String)) {
        let target = Date().addingTimeInterval(Double(preset.minutes * 60))
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: target)
        let minute = calendar.component(.minute, from: target)
        
        let quickAlarm = AlarmItem(
            title: preset.title,
            description: preset.desc,
            hour: hour,
            minute: minute,
            repeatDays: [], // One-time
            isEnabled: true,
            soundType: .digitalBeep,
            singVoiceEnabled: true,
            volumeBlast: true,
            challengeType: .instantClick,
            snoozeMinutes: 5
        )
        store.addAlarm(quickAlarm)
    }
}
