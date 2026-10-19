import SwiftUI

public struct MainDashboardView: View {
    @ObservedObject private var store = AlarmStore.shared
    @ObservedObject private var audioEngine = AudioEngine.shared
    
    @State private var showingAddSheet: Bool = false
    @State private var alarmToEdit: AlarmItem? = nil
    @State private var testCountdown: Int? = nil
    @State private var testTimer: Timer? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Hero Header
            heroHeader
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    // Quick Timers
                    QuickTimerView()
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                    
                    // Alarms List Section
                    alarmsListSection
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 32)
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        .sheet(isPresented: $showingAddSheet) {
            AlarmEditView { newAlarm in
                store.addAlarm(newAlarm)
            }
        }
        .sheet(item: $alarmToEdit) { alarm in
            AlarmEditView(alarmToEdit: alarm) { updated in
                store.updateAlarm(updated)
            }
        }
    }
    
    // MARK: - Hero Header
    
    private var heroHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                // Live Clock & Date
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "alarm.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                        Text("Mac Real Alarm")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                    }
                    
                    Text(formattedDate)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Giant Live Time
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedLiveTime)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 12) {
                    // TEST ALARM BUTTON
                    Button(action: {
                        triggerImmediateTest()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                            Text(testCountdown != nil ? "Starting in \(testCountdown!)s..." : "Test Alarm Now")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // ADD ALARM BUTTON
                    Button(action: {
                        showingAddSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add Alarm")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.red)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Next Upcoming Alarm Pill
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundColor(.red)
                Text(store.nextUpcomingSummary)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Text("Blocks screen fullscreen when ringing • Sings loud description")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var formattedLiveTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: store.currentTime)
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: store.currentTime)
    }
    
    private func formatSnooze(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    // MARK: - Alarms List
    
    private var alarmsListSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Scheduled Alarms (\(store.alarms.count))")
                    .font(.title3.weight(.bold))
                Spacer()
            }
            
            if store.alarms.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No alarms configured yet")
                        .font(.headline)
                    Text("Tap '+ Add Alarm' or choose a quick timer above to set your first real alarm.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(48)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(store.alarms) { alarm in
                        alarmRowCard(for: alarm)
                    }
                }
            }
        }
    }
    
    private func alarmRowCard(for alarm: AlarmItem) -> some View {
        HStack(spacing: 20) {
            // Time & Recurring
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.formattedTime)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(alarm.isEnabled ? .primary : .secondary)
                
                HStack(spacing: 6) {
                    Text(alarm.repeatDaysSummary)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.15))
                        )
                        .foregroundColor(.secondary)
                    
                    if alarm.isSnoozed, let snoozeUntil = alarm.snoozeUntil {
                        Text("Snoozed until \(formatSnooze(snoozeUntil))")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundColor(.orange)
                    }
                }
            }
            .frame(width: 170, alignment: .leading)
            
            // Title & Description
            VStack(alignment: .leading, spacing: 6) {
                Text(alarm.title.isEmpty ? "Alarm" : alarm.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(alarm.isEnabled ? .primary : .secondary)
                
                if !alarm.description.isEmpty {
                    Text(alarm.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Feature badges
                HStack(spacing: 8) {
                    Label(alarm.soundType.displayName, systemImage: alarm.soundType.iconName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if alarm.singVoiceEnabled {
                        Label("Sings Loud", systemImage: "waveform.badge.mic")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                    }
                    
                    if alarm.challengeType != .instantClick {
                        Label(alarm.challengeType.displayName, systemImage: alarm.challengeType.iconName)
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                // Test trigger button
                Button(action: {
                    store.testTriggerAlarm(alarm)
                }) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Test this alarm fullscreen immediately")
                
                // Edit button
                Button(action: {
                    alarmToEdit = alarm
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit Alarm")
                
                // Delete button
                Button(action: {
                    store.deleteAlarm(id: alarm.id)
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Delete Alarm")
                
                Divider()
                    .frame(height: 24)
                
                // Enable/Disable toggle
                Toggle("", isOn: Binding(
                    get: { alarm.isEnabled },
                    set: { _ in store.toggleAlarm(id: alarm.id) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(alarm.isEnabled ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1.5)
                )
        )
    }
    
    // MARK: - Immediate Test
    
    private func triggerImmediateTest() {
        let testAlarm = AlarmItem(
            title: "Demonstration Alarm",
            description: "This is a demonstration of the real fullscreen screen-blocking alarm with loud voice singing!",
            hour: Calendar.current.component(.hour, from: Date()),
            minute: Calendar.current.component(.minute, from: Date()),
            repeatDays: [],
            isEnabled: true,
            soundType: .digitalBeep,
            singVoiceEnabled: true,
            volumeBlast: true,
            challengeType: .instantClick,
            snoozeMinutes: 5
        )
        store.testTriggerAlarm(testAlarm)
    }
}
