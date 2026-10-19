import Foundation

public enum SoundType: String, Codable, CaseIterable, Identifiable, Sendable {
    case digitalBeep = "digital_beep"
    case twinBell = "twin_bell"
    case emergencySiren = "emergency_siren"
    case harmoniousWake = "harmonious_wake"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .digitalBeep: return "Digital Pulse Beeps"
        case .twinBell: return "Mechanical Twin-Bell"
        case .emergencySiren: return "Emergency Red Siren"
        case .harmoniousWake: return "Harmonious Marimba Chime"
        }
    }
    
    public var iconName: String {
        switch self {
        case .digitalBeep: return "waveform.path.badge.plus"
        case .twinBell: return "bell.badge.fill"
        case .emergencySiren: return "light.beacon.max.fill"
        case .harmoniousWake: return "music.note"
        }
    }
    
    public var descriptionText: String {
        switch self {
        case .digitalBeep: return "Sharp, high-frequency digital pulses designed for rapid awakening"
        case .twinBell: return "Resonant dual-frequency mechanical hammer bell strikes"
        case .emergencySiren: return "High-intensity oscillating siren with maximum psychoacoustic urgency"
        case .harmoniousWake: return "Uplifting warm major-chord resonance that builds momentum"
        }
    }
}

public enum ChallengeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case instantClick = "instant_click"
    case holdToDismiss = "hold_to_dismiss"
    case mathChallenge = "math_challenge"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .instantClick: return "Standard Dismiss"
        case .holdToDismiss: return "Hold for 3 Seconds"
        case .mathChallenge: return "Solve Math Problem"
        }
    }
    
    public var iconName: String {
        switch self {
        case .instantClick: return "hand.tap.fill"
        case .holdToDismiss: return "clock.arrow.circlepath"
        case .mathChallenge: return "function"
        }
    }
    
    public var descriptionText: String {
        switch self {
        case .instantClick: return "Single click or tap to dismiss"
        case .holdToDismiss: return "Must press and hold for 3 uninterrupted seconds"
        case .mathChallenge: return "Requires solving a wake-up arithmetic question to stop"
        }
    }
}

public struct AlarmItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var description: String
    public var hour: Int
    public var minute: Int
    public var repeatDays: [Int] // 1 = Sunday, 2 = Monday, ..., 7 = Saturday. Empty = one-time.
    public var isEnabled: Bool
    public var soundType: SoundType
    public var singVoiceEnabled: Bool
    public var volumeBlast: Bool
    public var challengeType: ChallengeType
    public var snoozeMinutes: Int
    public var isSnoozed: Bool
    public var snoozeUntil: Date?
    public var lastTriggeredDate: Date?
    
    public init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        hour: Int,
        minute: Int,
        repeatDays: [Int] = [],
        isEnabled: Bool = true,
        soundType: SoundType = .digitalBeep,
        singVoiceEnabled: Bool = true,
        volumeBlast: Bool = true,
        challengeType: ChallengeType = .instantClick,
        snoozeMinutes: Int = 9,
        isSnoozed: Bool = false,
        snoozeUntil: Date? = nil,
        lastTriggeredDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.hour = hour
        self.minute = minute
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
        self.soundType = soundType
        self.singVoiceEnabled = singVoiceEnabled
        self.volumeBlast = volumeBlast
        self.challengeType = challengeType
        self.snoozeMinutes = snoozeMinutes
        self.isSnoozed = isSnoozed
        self.snoozeUntil = snoozeUntil
        self.lastTriggeredDate = lastTriggeredDate
    }
    
    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        if let date = Calendar.current.date(from: comps) {
            return formatter.string(from: date)
        }
        return String(format: "%02d:%02d", hour, minute)
    }
    
    public var timeOnly24Hour: String {
        return String(format: "%02d:%02d", hour, minute)
    }
    
    public var repeatDaysSummary: String {
        if repeatDays.isEmpty {
            return "Once"
        }
        if repeatDays.count == 7 {
            return "Every day"
        }
        let weekdays = [2, 3, 4, 5, 6]
        let weekends = [1, 7]
        let sorted = repeatDays.sorted()
        if sorted == weekdays {
            return "Weekdays"
        }
        if sorted == weekends {
            return "Weekends"
        }
        
        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return sorted.compactMap { $0 < dayNames.count ? dayNames[$0] : nil }.joined(separator: ", ")
    }
    
    public func nextTriggerDate(from now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        
        // If currently snoozed, check snooze date
        if isSnoozed, let snoozeUntil = snoozeUntil {
            if snoozeUntil > now {
                return snoozeUntil
            }
        }
        
        guard isEnabled else { return nil }
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = 0
        
        if repeatDays.isEmpty {
            // One-time alarm
            var candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
            if candidate <= now {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
            }
            return candidate
        } else {
            // Recurring alarm on specific weekdays
            var nextDate: Date? = nil
            for day in 0...7 {
                guard let candidateDay = calendar.date(byAdding: .day, value: day, to: now) else { continue }
                let weekday = calendar.component(.weekday, from: candidateDay)
                if repeatDays.contains(weekday) {
                    guard let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: candidateDay) else { continue }
                    if candidate > now {
                        if nextDate == nil || candidate < nextDate! {
                            nextDate = candidate
                        }
                    }
                }
            }
            return nextDate
        }
    }
}
