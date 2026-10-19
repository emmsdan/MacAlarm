import Foundation

public struct SyncSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var email: String
    public var redisHost: String
    public var redisPort: Int
    public var redisPassword: String
    public var useTLS: Bool
    public var customChannel: String
    
    public init(
        isEnabled: Bool = false,
        email: String = "",
        redisHost: String = "127.0.0.1",
        redisPort: Int = 6379,
        redisPassword: String = "",
        useTLS: Bool = false,
        customChannel: String = ""
    ) {
        self.isEnabled = isEnabled
        self.email = email
        self.redisHost = redisHost
        self.redisPort = redisPort
        self.redisPassword = redisPassword
        self.useTLS = useTLS
        self.customChannel = customChannel
    }
    
    public var activeChannel: String {
        if !customChannel.trimmingCharacters(in: .whitespaces).isEmpty {
            return customChannel.trimmingCharacters(in: .whitespaces)
        }
        let cleanEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        if cleanEmail.isEmpty {
            return "alarm:sync:default"
        }
        // Normalize email to safe channel name
        let safeName = cleanEmail.replacingOccurrences(of: "@", with: "_at_").replacingOccurrences(of: ".", with: "_")
        return "alarm:sync:\(safeName)"
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
