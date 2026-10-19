import SwiftUI

public struct SyncSettingsView: View {
    @ObservedObject private var syncService = RedisSyncService.shared
    @ObservedObject private var store = AlarmStore.shared
    
    @State private var isEnabled: Bool = false
    @State private var email: String = ""
    @State private var isSyncingNow: Bool = false
    @State private var hasSavedNotification: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Banner
                headerCard
                
                // User Account Sync Card
                accountSyncCard
                
                // Status & Actions Card
                actionsCard
            }
            .padding(24)
        }
        .onAppear {
            loadCurrentSettings()
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 32))
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Device Cloud Sync")
                    .font(.system(size: 18, weight: .bold))
                
                Text("Seamlessly sync your alarms and reminders across your Macs.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(syncService.status.rawValue)
                    .font(.system(size: 12, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(statusColor.opacity(0.12)))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var statusColor: Color {
        switch syncService.status {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .secondary
        case .disabled: return .secondary
        }
    }
    
    // MARK: - Account Sync Card
    
    private var accountSyncCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Enable toggle
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync Alarms Across Devices")
                        .font(.headline)
                    Text("Automatically keeps your alarms updated whenever you make changes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: isEnabled) { _, _ in
                autoSave()
            }
            
            Divider()
            
            // Email Account
            VStack(alignment: .leading, spacing: 6) {
                Text("Your Email Address")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("e.g. yourname@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEnabled)
                    .onChange(of: email) { _, _ in autoSave() }
                
                Text("Alarms are tied to this email account so all your devices stay in sync.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if hasSavedNotification {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                    Text("Changes saved")
                        .font(.caption)
                }
                .foregroundColor(.green)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    // MARK: - Actions Card
    
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sync Controls & Status")
                .font(.headline)
            
            HStack(spacing: 14) {
                Button(action: {
                    triggerManualSync()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isSyncingNow ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        Text(isSyncingNow ? "Syncing..." : "Sync All Alarms Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!isEnabled || email.trimmingCharacters(in: .whitespaces).isEmpty || isSyncingNow)
                
                Spacer()
                
                if let lastSync = syncService.lastSyncDate {
                    Text("Last synced: \(formatLastSyncDate(lastSync))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Recent Activity
            if !syncService.syncLogs.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Activity")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 6) {
                        ForEach(syncService.syncLogs.prefix(5)) { log in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(log.isSuccess ? Color.green : Color.orange)
                                    .frame(width: 6, height: 6)
                                
                                Text(log.formattedTime)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                
                                Text(log.message)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private func formatLastSyncDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }
    
    // MARK: - Save Logic
    
    private func loadCurrentSettings() {
        let s = syncService.settings
        self.isEnabled = s.isEnabled
        self.email = s.email
    }
    
    private func autoSave() {
        var updated = syncService.settings
        updated.isEnabled = isEnabled
        updated.email = email.trimmingCharacters(in: .whitespaces)
        syncService.updateSettings(updated)
        
        hasSavedNotification = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            hasSavedNotification = false
        }
    }
    
    private func triggerManualSync() {
        isSyncingNow = true
        store.syncAllToRemote()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isSyncingNow = false
        }
    }
}
