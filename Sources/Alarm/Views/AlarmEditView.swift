import SwiftUI

public struct AlarmEditView: View {
    @Environment(\.dismiss) private var dismiss
    
    public var alarmToEdit: AlarmItem?
    public var onSave: (AlarmItem) -> Void
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedDate: Date = Date()
    @State private var repeatDays: Set<Int> = []
    @State private var soundType: SoundType = .digitalBeep
    @State private var singVoiceEnabled: Bool = true
    @State private var volumeBlast: Bool = true
    @State private var challengeType: ChallengeType = .instantClick
    @State private var snoozeMinutes: Int = 9
    
    @ObservedObject private var audioEngine = AudioEngine.shared
    
    private let weekdays = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"),
        (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]
    
    public init(alarmToEdit: AlarmItem? = nil, onSave: @escaping (AlarmItem) -> Void) {
        self.alarmToEdit = alarmToEdit
        self.onSave = onSave
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(alarmToEdit == nil ? "New Alarm" : "Edit Alarm")
                    .font(.system(size: 20, weight: .bold))
                
                Spacer()
                
                Button("Cancel") {
                    audioEngine.stopRinging()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    saveAlarm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Quick Preset Templates (if new alarm)
                    if alarmToEdit == nil {
                        presetsSection
                    }
                    
                    // Time Picker Section
                    timePickerSection
                    
                    // Title & Description Section
                    titleAndDescriptionSection
                    
                    // Repeat Days Section
                    repeatDaysSection
                    
                    // Sound & Voice Section (Rings & Sings Loud!)
                    soundAndVoiceSection
                    
                    // Dismiss Challenge & Snooze Section
                    challengeAndSnoozeSection
                }
                .padding(24)
            }
        }
        .frame(width: 540, height: 680)
        .onAppear {
            setupInitialValues()
        }
    }
    
    // MARK: - Sections
    
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Presets")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    presetChip(
                        name: "🌅 Morning Wake-Up",
                        hour: 7, minute: 30,
                        title: "Morning Wake Up",
                        desc: "Rise and shine! Time to conquer the day with high energy!",
                        sound: .digitalBeep,
                        days: [2, 3, 4, 5, 6],
                        challenge: .instantClick
                    )
                    presetChip(
                        name: "⚡ Deep Focus Sprint",
                        hour: 11, minute: 0,
                        title: "Deep Focus Sprint Complete",
                        desc: "Great focus session! Stand up, stretch, and rest your eyes.",
                        sound: .harmoniousWake,
                        days: [2, 3, 4, 5, 6],
                        challenge: .instantClick
                    )
                    presetChip(
                        name: "🔥 Heavy Sleeper",
                        hour: 6, minute: 30,
                        title: "Wake Up Right Now!",
                        desc: "Get out of bed immediately! Solve the puzzle to turn this off!",
                        sound: .emergencySiren,
                        days: [1, 2, 3, 4, 5, 6, 7],
                        challenge: .mathChallenge
                    )
                    presetChip(
                        name: "💊 Daily Medicine",
                        hour: 9, minute: 0,
                        title: "Take Daily Medication",
                        desc: "Time to take your vitamins and prescribed medication.",
                        sound: .twinBell,
                        days: [1, 2, 3, 4, 5, 6, 7],
                        challenge: .instantClick
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private func presetChip(name: String, hour: Int, minute: Int, title: String, desc: String, sound: SoundType, days: [Int], challenge: ChallengeType) -> some View {
        Button(action: {
            self.title = title
            self.description = desc
            self.soundType = sound
            self.repeatDays = Set(days)
            self.challengeType = challenge
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            if let date = Calendar.current.date(from: comps) {
                self.selectedDate = date
            }
        }) {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.quaternaryLabelColor).opacity(0.6))
                )
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
    
    private var timePickerSection: some View {
        VStack(spacing: 8) {
            Text("Alarm Time")
                .font(.headline)
            
            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.stepperField)
            .labelsHidden()
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var titleAndDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Alarm Details")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Label / Title")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("e.g. Wake Up & Exercise", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Description (Shown fullscreen & spoken aloud)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if singVoiceEnabled {
                        Text("🗣️ Will be spoken")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                TextField("e.g. Get out of bed, drink water, and conquer your goals!", text: $description)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var repeatDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Repeat Schedule")
                    .font(.headline)
                Spacer()
                // Quick preset buttons
                Button("Weekdays") {
                    repeatDays = [2, 3, 4, 5, 6]
                }
                .buttonStyle(.borderless)
                .font(.caption)
                
                Button("Daily") {
                    repeatDays = [1, 2, 3, 4, 5, 6, 7]
                }
                .buttonStyle(.borderless)
                .font(.caption)
                
                Button("Once") {
                    repeatDays = []
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            
            HStack(spacing: 8) {
                ForEach(weekdays, id: \.0) { day in
                    let isSelected = repeatDays.contains(day.0)
                    Button(action: {
                        if isSelected {
                            repeatDays.remove(day.0)
                        } else {
                            repeatDays.insert(day.0)
                        }
                    }) {
                        Text(day.1)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.red : Color(NSColor.quaternaryLabelColor))
                            )
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var soundAndVoiceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio & Singing Engine")
                .font(.headline)
            
            // Sound Type Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Ringtone Sound")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Picker("", selection: $soundType) {
                        ForEach(SoundType.allCases) { sound in
                            Text(sound.displayName).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Button(action: {
                        audioEngine.previewSound(soundType)
                    }) {
                        Label("Preview", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Divider()
            
            // Sing Description Switch
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $singVoiceEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sing / Announce Description Aloud")
                            .font(.body.weight(.medium))
                        Text("Repeatedly speaks the alarm title and description loudly through voice synthesis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                
                if singVoiceEnabled {
                    Button(action: {
                        audioEngine.previewVoice(text: description.isEmpty ? title : description)
                    }) {
                        Label("Preview Spoken Voice", systemImage: "waveform.badge.mic")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            Divider()
            
            // Max Volume Blast Switch
            Toggle(isOn: $volumeBlast) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("100% Maximum Volume Blast")
                        .font(.body.weight(.medium))
                    Text("Automatically sets Mac system volume to 100% when ringing and restores after dismiss")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var challengeAndSnoozeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dismissal & Snooze")
                .font(.headline)
            
            // Challenge type
            VStack(alignment: .leading, spacing: 8) {
                Text("Wake-Up Dismiss Requirement")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $challengeType) {
                    ForEach(ChallengeType.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                
                Text(challengeType.descriptionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Snooze time
            HStack {
                Text("Snooze Duration")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $snoozeMinutes) {
                    Text("5 Minutes").tag(5)
                    Text("9 Minutes (Standard)").tag(9)
                    Text("15 Minutes").tag(15)
                    Text("20 Minutes").tag(20)
                }
                .frame(width: 180)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    // MARK: - Save Logic
    
    private func setupInitialValues() {
        if let alarm = alarmToEdit {
            title = alarm.title
            description = alarm.description
            soundType = alarm.soundType
            singVoiceEnabled = alarm.singVoiceEnabled
            volumeBlast = alarm.volumeBlast
            challengeType = alarm.challengeType
            snoozeMinutes = alarm.snoozeMinutes
            repeatDays = Set(alarm.repeatDays)
            
            var comps = DateComponents()
            comps.hour = alarm.hour
            comps.minute = alarm.minute
            if let date = Calendar.current.date(from: comps) {
                selectedDate = date
            }
        } else {
            // Default 15 minutes in the future for quick testing
            selectedDate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        }
    }
    
    private func saveAlarm() {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selectedDate)
        let minute = calendar.component(.minute, from: selectedDate)
        
        let finalTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Alarm" : title.trimmingCharacters(in: .whitespaces)
        
        let newAlarm = AlarmItem(
            id: alarmToEdit?.id ?? UUID(),
            title: finalTitle,
            description: description.trimmingCharacters(in: .whitespaces),
            hour: hour,
            minute: minute,
            repeatDays: Array(repeatDays).sorted(),
            isEnabled: true,
            soundType: soundType,
            singVoiceEnabled: singVoiceEnabled,
            volumeBlast: volumeBlast,
            challengeType: challengeType,
            snoozeMinutes: snoozeMinutes
        )
        
        audioEngine.stopRinging()
        onSave(newAlarm)
        dismiss()
    }
}
