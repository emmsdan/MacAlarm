import SwiftUI

public enum DashboardTab: String, CaseIterable, Identifiable {
    case alarms = "Alarms"
    case quickTimers = "Quick Focus"
    case cloudSync = "Cloud Sync"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .alarms: return "alarm.fill"
        case .quickTimers: return "timer"
        case .cloudSync: return "cloud.fill"
        }
    }
}

public struct MainDashboardView: View {
    @ObservedObject private var store = AlarmStore.shared
    @ObservedObject private var syncService = RedisSyncService.shared
    
    @State private var selectedTab: DashboardTab = .alarms
    @State private var showingAddSheet: Bool = false
    @State private var alarmToEdit: AlarmItem? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Elegant Hero Header
            heroHeader
            
            Divider()
            
            // Tab Content
            switch selectedTab {
            case .alarms:
                alarmsTabContent
            case .quickTimers:
                quickTimersTabContent
            case .cloudSync:
                SyncSettingsView()
            }
        }
        .frame(minWidth: 760, minHeight: 660)
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
                // Greeting & Brand
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "alarm.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                        Text("Real Alarm")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                    }
                    
                    Text("\(greetingText), Emmsdan")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Giant Live Time Display
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedLiveTime)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                )
                
                Spacer()
                
                // Primary Action Button (+ Add Alarm)
                Button(action: {
                    showingAddSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("New Alarm")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Color.red, Color(red: 0.85, green: 0.15, blue: 0.15)], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Color.red.opacity(0.3), radius: 6, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
            }
            
            // Sub-bar: Navigation Segmented Control & Status Info
            HStack(spacing: 16) {
                // Segmented Tabs
                HStack(spacing: 4) {
                    ForEach(DashboardTab.allCases) { tab in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedTab = tab
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 12))
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: selectedTab == tab ? .bold : .medium))
                                
                                if tab == .alarms {
                                    Text("\(store.alarms.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(selectedTab == tab ? Color.red : Color.secondary.opacity(0.2)))
                                        .foregroundColor(selectedTab == tab ? .white : .secondary)
                                } else if tab == .cloudSync && syncService.settings.isEnabled {
                                    Circle()
                                        .fill(syncService.status == .connected ? Color.green : Color.orange)
                                        .frame(width: 7, height: 7)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedTab == tab ? Color(NSColor.controlBackgroundColor) : Color.clear)
                            )
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.quaternaryLabelColor).opacity(0.5))
                )
                
                Spacer()
                
                // Next upcoming alarm indicator
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundColor(.red)
                    Text(store.nextUpcomingSummary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.08))
                )
            }
        }
        .padding(20)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Dynamic Greetings & Formatting
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: store.currentTime)
        if hour >= 5 && hour < 12 {
            return "Good morning 🌅"
        } else if hour >= 12 && hour < 17 {
            return "Good afternoon ☀️"
        } else if hour >= 17 && hour < 22 {
            return "Good evening 🌇"
        } else {
            return "Night owl time 🌙"
        }
    }
    
    private var formattedLiveTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: store.currentTime)
    }
    
    private func formatSnooze(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    // MARK: - Alarms Tab Content
    
    private var alarmsTabContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                if store.alarms.isEmpty {
                    emptyAlarmsView
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 12) {
                        ForEach(store.alarms) { alarm in
                            alarmCard(for: alarm)
                        }
                    }
                    .padding(24)
                }
            }
            .padding(.bottom, 24)
        }
    }
    
    private var emptyAlarmsView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "bell.badge")
                    .font(.system(size: 36))
                    .foregroundColor(.red)
            }
            
            Text("No Alarms Set")
                .font(.title3.weight(.bold))
            
            Text("Create a real alarm that blocks your screen fullscreen and sings your description aloud.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            
            Button("Create First Alarm") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }
    
    private func alarmCard(for alarm: AlarmItem) -> some View {
        HStack(spacing: 20) {
            // Time and Recurring Days
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.formattedTime)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(alarm.isEnabled ? .primary : .secondary)
                
                HStack(spacing: 6) {
                    Text(alarm.repeatDaysSummary)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.secondary.opacity(0.14))
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
                        Label("Sings Description", systemImage: "waveform.badge.mic")
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
                // Edit button
                Button(action: {
                    alarmToEdit = alarm
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(8)
                        .background(Circle().fill(Color(NSColor.quaternaryLabelColor).opacity(0.5)))
                }
                .buttonStyle(.plain)
                .help("Edit Alarm")
                
                // Duplicate button
                Button(action: {
                    duplicateAlarm(alarm)
                }) {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(8)
                        .background(Circle().fill(Color(NSColor.quaternaryLabelColor).opacity(0.5)))
                }
                .buttonStyle(.plain)
                .help("Duplicate Alarm")
                
                // Delete button
                Button(action: {
                    withAnimation {
                        store.deleteAlarm(id: alarm.id)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))
                        .padding(8)
                        .background(Circle().fill(Color.red.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Delete Alarm")
                
                Divider()
                    .frame(height: 24)
                
                // Enable/Disable switch
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
                        .stroke(alarm.isEnabled ? Color.red.opacity(0.25) : Color.clear, lineWidth: 1.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            alarmToEdit = alarm
        }
    }
    
    private func duplicateAlarm(_ alarm: AlarmItem) {
        var copy = alarm
        copy.id = UUID()
        copy.title = "\(alarm.title) (Copy)"
        store.addAlarm(copy)
    }
    
    // MARK: - Quick Timers Tab Content
    
    private var quickTimersTabContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                QuickTimerView()
                    .padding(24)
            }
        }
    }
}
