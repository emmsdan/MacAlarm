import Foundation

public struct SyncSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var email: String
    
    // Internal/Advanced server overrides if specified via env or file
    public var customHost: String?
    public var customPort: Int?
    public var customPassword: String?
    public var customUseTLS: Bool?
    public var customChannel: String?
    
    public init(
        isEnabled: Bool = false,
        email: String = "",
        customHost: String? = nil,
        customPort: Int? = nil,
        customPassword: String? = nil,
        customUseTLS: Bool? = nil,
        customChannel: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.email = email
        self.customHost = customHost
        self.customPort = customPort
        self.customPassword = customPassword
        self.customUseTLS = customUseTLS
        self.customChannel = customChannel
    }
    
    public var activeChannel: String {
        if let custom = customChannel, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom.trimmingCharacters(in: .whitespaces)
        }
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        if cleanEmail.isEmpty {
            return "macalarm:sync:default"
        }
        // Normalize email to safe channel name
        let safeName = cleanEmail.replacingOccurrences(of: "@", with: "_at_").replacingOccurrences(of: ".", with: "_")
        let prefix = ProcessInfo.processInfo.environment["REDIS_CHANNEL_PREFIX"] ?? "macalarm:sync:"
        return "\(prefix)\(safeName)"
    }
}

public enum SyncAction: String, Codable, Sendable {
    case syncAll = "sync_all"
    case upsertAlarm = "upsert_alarm"
    case deleteAlarm = "delete_alarm"
    case remoteTrigger = "remote_trigger"
    case remoteDismiss = "remote_dismiss"
    case remoteSnooze = "remote_snooze"
}

public struct SyncMessage: Codable, Sendable {
    public var eventId: String
    public var senderDeviceId: String
    public var email: String
    public var timestamp: TimeInterval
    public var action: SyncAction
    public var alarm: AlarmItem?
    public var alarms: [AlarmItem]?
    
    public init(
        eventId: String = UUID().uuidString,
        senderDeviceId: String,
        email: String,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        action: SyncAction,
        alarm: AlarmItem? = nil,
        alarms: [AlarmItem]? = nil
    ) {
        self.eventId = eventId
        self.senderDeviceId = senderDeviceId
        self.email = email
        self.timestamp = timestamp
        self.action = action
        self.alarm = alarm
        self.alarms = alarms
    }
}

public struct SyncLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let message: String
    public let isSuccess: Bool
    
    public init(timestamp: Date = Date(), message: String, isSuccess: Bool = true) {
        self.timestamp = timestamp
        self.message = message
        self.isSuccess = isSuccess
    }
    
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
