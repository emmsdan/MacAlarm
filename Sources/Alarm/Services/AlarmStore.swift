import Foundation
import Combine

@MainActor
public final class AlarmStore: ObservableObject {
    public static let shared = AlarmStore()
    
    @Published public var alarms: [AlarmItem] = []
    @Published public var currentlyRingingAlarm: AlarmItem? = nil
    @Published public var currentTime: Date = Date()
    
    private var timer: Timer?
    private let saveFileURL: URL
    
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.alarm.macapp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.saveFileURL = dir.appendingPathComponent("alarms.json")
        
        loadAlarms()
        startHeartbeat()
    }
    
    // MARK: - Heartbeat & Check Loop
    
    private func startHeartbeat() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }
    
    private func tick() {
        let now = Date()
        self.currentTime = now
        
        // If already ringing an alarm, don't trigger another concurrently
        if currentlyRingingAlarm != nil {
            return
        }
        
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)
        
        for (index, alarm) in alarms.enumerated() {
            guard alarm.isEnabled else { continue }
            
            // Check snoozed alarms
            if alarm.isSnoozed, let snoozeUntil = alarm.snoozeUntil {
                if now >= snoozeUntil {
                    // Snooze elapsed! Trigger!
                    var updated = alarm
                    updated.isSnoozed = false
                    updated.snoozeUntil = nil
                    alarms[index] = updated
                    saveAlarms()
                    triggerAlarm(updated)
                    return
                }
                continue
            }
            
            // Regular schedule check
            if alarm.hour == currentHour && alarm.minute == currentMinute {
                // Verify weekday matches if recurring
                if !alarm.repeatDays.isEmpty && !alarm.repeatDays.contains(currentWeekday) {
                    continue
                }
                
                // Prevent multiple triggers in the same minute
                if let lastTrigger = alarm.lastTriggeredDate,
                   calendar.isDate(lastTrigger, equalTo: now, toGranularity: .minute) {
                    continue
                }
                
                // Trigger!
                var updated = alarm
                updated.lastTriggeredDate = now
                if alarm.repeatDays.isEmpty {
                    // One-time alarm will be disabled when dismissed
                }
                alarms[index] = updated
                saveAlarms()
                triggerAlarm(updated)
                return
            }
        }
    }
    
    // MARK: - Alarm Trigger, Dismiss, Snooze
    
    public func triggerAlarm(_ alarm: AlarmItem) {
        self.currentlyRingingAlarm = alarm
        
        // Prevent display sleep
        SleepAssertionManager.shared.preventSleep(reason: "Alarm: \(alarm.title)")
        
        // Block screen fullscreen
        FullScreenAlarmManager.shared.showFullScreen(for: alarm)
        
        // Play sound and sing description loud
        AudioEngine.shared.startRinging(for: alarm)
    }
    
    public func testTriggerAlarm(_ alarm: AlarmItem) {
        triggerAlarm(alarm)
    }
    
    public func dismissCurrentlyRinging() {
        guard let alarm = currentlyRingingAlarm else { return }
        
        AudioEngine.shared.stopRinging()
        FullScreenAlarmManager.shared.dismiss()
        SleepAssertionManager.shared.releaseSleep()
        
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            var updated = alarms[idx]
            updated.isSnoozed = false
            updated.snoozeUntil = nil
            if updated.repeatDays.isEmpty {
                // One-time alarm gets turned off after dismissal
                updated.isEnabled = false
            }
            alarms[idx] = updated
            saveAlarms()
        }
        
        self.currentlyRingingAlarm = nil
    }
    
    public func snoozeCurrentlyRinging(customMinutes: Int? = nil) {
        guard let alarm = currentlyRingingAlarm else { return }
        
        AudioEngine.shared.stopRinging()
        FullScreenAlarmManager.shared.dismiss()
        SleepAssertionManager.shared.releaseSleep()
        
        let minutes = customMinutes ?? alarm.snoozeMinutes
        let snoozeDate = Date().addingTimeInterval(Double(minutes * 60))
        
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            var updated = alarms[idx]
            updated.isSnoozed = true
            updated.snoozeUntil = snoozeDate
            alarms[idx] = updated
            saveAlarms()
        }
        
        self.currentlyRingingAlarm = nil
    }
    
    // MARK: - CRUD
    
    public func addAlarm(_ alarm: AlarmItem) {
        alarms.append(alarm)
        sortAlarms()
        saveAlarms()
    }
    
    public func updateAlarm(_ alarm: AlarmItem) {
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx] = alarm
            sortAlarms()
            saveAlarms()
        }
    }
    
    public func deleteAlarm(id: UUID) {
        alarms.removeAll { $0.id == id }
        saveAlarms()
    }
    
    public func toggleAlarm(id: UUID) {
        if let idx = alarms.firstIndex(where: { $0.id == id }) {
            alarms[idx].isEnabled.toggle()
            if !alarms[idx].isEnabled {
                alarms[idx].isSnoozed = false
                alarms[idx].snoozeUntil = nil
            }
            saveAlarms()
        }
    }
    
    private func sortAlarms() {
        alarms.sort { (a, b) -> Bool in
            if a.hour != b.hour {
                return a.hour < b.hour
            }
            return a.minute < b.minute
        }
    }
    
    // MARK: - Next Upcoming Alarm
    
    public var nextUpcomingAlarm: (alarm: AlarmItem, triggerDate: Date)? {
        let now = Date()
        var upcoming: (alarm: AlarmItem, triggerDate: Date)? = nil
        
        for alarm in alarms where alarm.isEnabled {
            if let trigger = alarm.nextTriggerDate(from: now) {
                if upcoming == nil || trigger < upcoming!.triggerDate {
                    upcoming = (alarm, trigger)
                }
            }
        }
        
        return upcoming
    }
    
    public var nextUpcomingSummary: String {
        guard let next = nextUpcomingAlarm else {
            return "No alarms scheduled"
        }
        
        let diff = Int(next.triggerDate.timeIntervalSince(Date()))
        if diff <= 0 {
            return "Alarm due now"
        }
        
        let hours = diff / 3600
        let minutes = (diff % 3600) / 60
        
        if hours > 0 {
            return "Next alarm in \(hours)h \(minutes)m (\(next.alarm.formattedTime))"
        } else {
            return "Next alarm in \(minutes)m (\(next.alarm.formattedTime))"
        }
    }
    
    // MARK: - Persistence
    
    private func loadAlarms() {
        if FileManager.default.fileExists(atPath: saveFileURL.path) {
            do {
                let data = try Data(contentsOf: saveFileURL)
                let decoded = try JSONDecoder().decode([AlarmItem].self, from: data)
                self.alarms = decoded
                sortAlarms()
                return
            } catch {
                print("Failed to decode alarms: \(error)")
            }
        }
        
        // Defaults on first launch
        self.alarms = [
            AlarmItem(
                title: "Morning Wake Up",
                description: "Rise and shine! Time to conquer the day with high energy!",
                hour: 7,
                minute: 30,
                repeatDays: [2, 3, 4, 5, 6], // Weekdays
                isEnabled: true,
                soundType: .digitalBeep,
                singVoiceEnabled: true,
                volumeBlast: true,
                challengeType: .instantClick,
                snoozeMinutes: 9
            ),
            AlarmItem(
                title: "Midday Reset & Hydration",
                description: "Step away from screens, drink a tall glass of cold water, and stretch your body!",
                hour: 13,
                minute: 0,
                repeatDays: [2, 3, 4, 5, 6],
                isEnabled: false,
                soundType: .harmoniousWake,
                singVoiceEnabled: true,
                volumeBlast: true,
                challengeType: .instantClick,
                snoozeMinutes: 5
            )
        ]
        sortAlarms()
        saveAlarms()
    }
    
    private func saveAlarms() {
        do {
            let data = try JSONEncoder().encode(alarms)
            try data.write(to: saveFileURL, options: .atomic)
        } catch {
            print("Failed to save alarms: \(error)")
        }
    }
}
