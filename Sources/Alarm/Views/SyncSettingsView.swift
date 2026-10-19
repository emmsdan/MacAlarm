import SwiftUI

public struct SyncSettingsView: View {
    @ObservedObject private var syncService = RedisSyncService.shared
    @ObservedObject private var store = AlarmStore.shared
    
    @State private var isEnabled: Bool = false
    @State private var email: String = ""
    @State private var redisHost: String = "127.0.0.1"
    @State private var redisPort: String = "6379"
    @State private var redisPassword: String = ""
    @State private var useTLS: Bool = false
    @State private var customChannel: String = ""
    
    @State private var isTesting: Bool = false
    @State private var testResultMessage: String? = nil
    @State private var testResultSuccess: Bool = false
    @State private var hasSavedNotification: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Banner
                headerCard
                
                // Account & Server Config Card
                configCard
                
                // Connection Testing & Manual Sync
                actionsCard
                
                // Activity Log Card
                activityLogCard
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
                Text("Email & Redis Cloud Synchronization")
                    .font(.system(size: 18, weight: .bold))
                
                Text("Synchronize your alarms across multiple Macs or remote controllers in real-time via Redis Pub/Sub.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
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
    
    // MARK: - Config Card
    
    private var configCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Enable toggle
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Remote Cloud Synchronization")
                        .font(.headline)
                    Text("Publishes and listens for alarm updates using your account channel")
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
                Text("Account Email Address")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextField("e.g. user@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEnabled)
                    .onChange(of: email) { _, _ in autoSave() }
                
                if !email.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Pub/Sub Channel: \(computedChannel)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // Redis Server Settings
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Redis Server Host / IP")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("127.0.0.1 or redis.example.com", text: $redisHost)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!isEnabled)
                        .onChange(of: redisHost) { _, _ in autoSave() }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Port")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("6379", text: $redisPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .disabled(!isEnabled)
                        .onChange(of: redisPort) { _, _ in autoSave() }
                }
            }
            
            // Redis Password & TLS
            VStack(alignment: .leading, spacing: 6) {
                Text("Password / Auth Token (Optional)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                SecureField("Leave empty if none required", text: $redisPassword)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEnabled)
                    .onChange(of: redisPassword) { _, _ in autoSave() }
            }
            
            HStack {
                Toggle("Use TLS / SSL Encryption (Port 6380)", isOn: $useTLS)
                    .disabled(!isEnabled)
                    .onChange(of: useTLS) { _, _ in autoSave() }
                
                Spacer()
                
                if hasSavedNotification {
                    Text("Settings saved")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var computedChannel: String {
        let clean = email.lowercased().trimmingCharacters(in: .whitespaces)
        if clean.isEmpty { return "alarm:sync:default" }
        let safe = clean.replacingOccurrences(of: "@", with: "_at_").replacingOccurrences(of: ".", with: "_")
        return "alarm:sync:\(safe)"
    }
    
    // MARK: - Actions Card
    
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connection & Actions")
                .font(.headline)
            
            HStack(spacing: 14) {
                // Test Connection Button
                Button(action: {
                    runTestConnection()
                }) {
                    HStack(spacing: 6) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "network")
                        }
                        Text(isTesting ? "Testing..." : "Test Redis Connection")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || !isEnabled)
                
                // Sync All Now Button
                Button(action: {
                    store.syncAllToRemote()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync All Alarms to Cloud Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!isEnabled)
                
                Spacer()
                
                if let lastSync = syncService.lastSyncDate {
                    Text("Last synced: \(formatLastSyncDate(lastSync))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let msg = testResultMessage {
                HStack(spacing: 8) {
                    Image(systemName: testResultSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(testResultSuccess ? .green : .red)
                    Text(msg)
                        .font(.system(size: 13))
                        .foregroundColor(testResultSuccess ? .green : .red)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((testResultSuccess ? Color.green : Color.red).opacity(0.1))
                )
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
    
    // MARK: - Activity Log
    
    private var activityLogCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sync Activity Log")
                    .font(.headline)
                Spacer()
                Text("Device ID: \(syncService.deviceId.prefix(8))...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            if syncService.syncLogs.isEmpty {
                Text("No sync activity yet. Connect to a Redis server to begin real-time pub/sub synchronization.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(syncService.syncLogs.prefix(10)) { log in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(log.isSuccess ? Color.green : Color.red)
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
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    // MARK: - Persistence & Test
    
    private func loadCurrentSettings() {
        let s = syncService.settings
        self.isEnabled = s.isEnabled
        self.email = s.email
        self.redisHost = s.redisHost
        self.redisPort = String(s.redisPort)
        self.redisPassword = s.redisPassword
        self.useTLS = s.useTLS
        self.customChannel = s.customChannel
    }
    
    private func autoSave() {
        let portInt = Int(redisPort.trimmingCharacters(in: .whitespaces)) ?? 6379
        let newSettings = SyncSettings(
            isEnabled: isEnabled,
            email: email.trimmingCharacters(in: .whitespaces),
            redisHost: redisHost.trimmingCharacters(in: .whitespaces),
            redisPort: portInt,
            redisPassword: redisPassword,
            useTLS: useTLS,
            customChannel: customChannel.trimmingCharacters(in: .whitespaces)
        )
        syncService.updateSettings(newSettings)
        
        hasSavedNotification = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            hasSavedNotification = false
        }
    }
    
    private func runTestConnection() {
        isTesting = true
        testResultMessage = nil
        
        // Ensure latest values are saved
        autoSave()
        
        syncService.testConnection { success, message in
            Task { @MainActor in
                self.isTesting = false
                self.testResultSuccess = success
                self.testResultMessage = message
            }
        }
    }
}
