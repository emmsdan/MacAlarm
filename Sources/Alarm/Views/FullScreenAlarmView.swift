import SwiftUI

public struct FullScreenAlarmView: View {
    public let alarm: AlarmItem
    
    @ObservedObject private var store = AlarmStore.shared
    @ObservedObject private var audioEngine = AudioEngine.shared
    
    @State private var pulseBackground: Bool = false
    @StateObject private var holdState = HoldDismissState()
    
    // Math Challenge state
    @State private var mathProblem: String = ""
    @State private var mathAnswer: Int = 0
    @State private var userAnswer: String = ""
    @State private var mathError: Bool = false
    
    public init(alarm: AlarmItem) {
        self.alarm = alarm
    }
    
    public var body: some View {
        ZStack {
            // 1. Dynamic Pulsing Background
            backgroundLayer
            
            // 2. Main Content
            VStack(spacing: 24) {
                // Top Status Badges
                topStatusHeader
                    .padding(.top, 40)
                
                Spacer()
                
                // Clock & Date Section
                clockSection
                
                // Live Audio Spectrum Visualizer
                VisualizerView(barColor: .red)
                    .padding(.vertical, 8)
                
                // Alarm Title & Description Card (Loudly displayed!)
                descriptionCard
                    .padding(.horizontal, 48)
                
                Spacer()
                
                // Action Controls (Dismiss & Snooze)
                controlsSection
                    .padding(.bottom, 50)
            }
            .frame(maxWidth: 1100)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseBackground = true
            }
            if alarm.challengeType == .mathChallenge {
                generateMathProblem()
            }
        }
    }
    
    // MARK: - Background Layer
    
    private var backgroundLayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Ambient red/amber pulse
            RadialGradient(
                colors: [
                    Color.red.opacity(pulseBackground ? 0.45 : 0.20),
                    Color.orange.opacity(pulseBackground ? 0.25 : 0.10),
                    Color.black.opacity(0.95)
                ],
                center: .center,
                startRadius: 50,
                endRadius: pulseBackground ? 900 : 650
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulseBackground)
            
            // Subtle tech grid lines
            Rectangle()
                .stroke(Color.red.opacity(0.08), lineWidth: 1)
                .ignoresSafeArea()
        }
    }
    
    // MARK: - Top Header
    
    private var topStatusHeader: some View {
        HStack(spacing: 16) {
            Label("ALARM ACTIVE", systemImage: "bell.fill")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.red.opacity(0.85)))
                .shadow(color: .red.opacity(0.6), radius: 10)
            
            Label("SCREEN-LOCK ENGAGED", systemImage: "lock.shield.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.5)).overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)))
            
            if alarm.volumeBlast {
                Label("100% VOLUME BLAST", systemImage: "speaker.wave.3.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.5)).overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)))
            }
            
            if alarm.singVoiceEnabled {
                Label("VOICE ANNOUNCEMENT ACTIVE", systemImage: "waveform.badge.mic")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.5)).overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)))
            }
        }
    }
    
    // MARK: - Clock & Date
    
    private var clockSection: some View {
        VStack(spacing: 8) {
            Text(formattedCurrentTime)
                .font(.system(size: 108, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .red.opacity(0.7), radius: 24, x: 0, y: 0)
                .monospacedDigit()
            
            Text(formattedCurrentDate.uppercased())
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .tracking(4)
        }
    }
    
    private var formattedCurrentTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: store.currentTime)
    }
    
    private var formattedCurrentDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: store.currentTime)
    }
    
    // MARK: - Description Card
    
    private var descriptionCard: some View {
        VStack(spacing: 12) {
            // Alarm Title
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundColor(.red)
                
                Text(alarm.title.isEmpty ? "Wake Up!" : alarm.title)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Description Text
            if !alarm.description.isEmpty {
                VStack(spacing: 8) {
                    Text(alarm.description)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                    
                    if alarm.singVoiceEnabled {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption)
                            Text("Speaking aloud & singing loud")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.top, 4)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .frame(maxWidth: 800)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [Color.red.opacity(0.7), Color.orange.opacity(0.3), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .shadow(color: .red.opacity(0.3), radius: 20)
        )
    }
    
    // MARK: - Controls Section
    
    private var controlsSection: some View {
        VStack(spacing: 20) {
            // Challenge controls if math
            if alarm.challengeType == .mathChallenge {
                mathChallengeUI
            }
            
            HStack(spacing: 24) {
                // SNOOZE BUTTON
                Button(action: {
                    store.snoozeCurrentlyRinging()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.title3)
                        Text("SNOOZE (\(alarm.snoozeMinutes) MIN)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(minWidth: 220, minHeight: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                
                // DISMISS BUTTON / HOLD
                if alarm.challengeType == .instantClick {
                    instantDismissButton
                } else if alarm.challengeType == .holdToDismiss {
                    holdToDismissButton
                }
            }
            
            // Keyboard hint
            Text("Tip: Spacebar to Snooze • Esc is locked")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // Instant Dismiss Button
    private var instantDismissButton: some View {
        Button(action: {
            store.dismissCurrentlyRinging()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                Text("DISMISS ALARM")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(minWidth: 260, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color(red: 0.8, green: 0.1, blue: 0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                    )
                    .shadow(color: .red.opacity(0.6), radius: 15)
            )
        }
        .buttonStyle(.plain)
    }
    
    // Hold to Dismiss Button
    private var holdToDismissButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.red.opacity(0.3))
                .frame(width: 280, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.red, lineWidth: 2)
                )
            
            // Progress fill
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.red)
                    .frame(width: geo.size.width * holdState.progress)
            }
            .frame(width: 280, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            
            HStack(spacing: 10) {
                Image(systemName: holdState.isHolding ? "lock.open.fill" : "hand.tap.fill")
                Text(holdState.isHolding ? "HOLDING... \(Int(holdState.progress * 100))%" : "HOLD 3 SECONDS TO STOP")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundColor(.white)
        }
        .onLongPressGesture(minimumDuration: 3.0, maximumDistance: 50, pressing: { pressing in
            if pressing {
                holdState.startHold {
                    store.dismissCurrentlyRinging()
                }
            } else {
                holdState.cancelHold()
            }
        }, perform: {
            store.dismissCurrentlyRinging()
        })
    }
    
    // Math Challenge UI
    private var mathChallengeUI: some View {
        VStack(spacing: 14) {
            Text("Solve this puzzle to prove you are awake:")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            
            HStack(spacing: 16) {
                Text(mathProblem)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                
                TextField("Your answer", text: $userAnswer)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .frame(width: 140, height: 48)
                    .multilineTextAlignment(.center)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(mathError ? Color.red : Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .onSubmit {
                        checkMathAnswer()
                    }
                
                Button("Unlock") {
                    checkMathAnswer()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
            
            if mathError {
                Text("Incorrect! Try again.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.75)))
    }
    
    private func generateMathProblem() {
        let a = Int.random(in: 12...49)
        let b = Int.random(in: 11...39)
        mathAnswer = a + b
        mathProblem = "\(a) + \(b) = ?"
        userAnswer = ""
        mathError = false
    }
    
    private func checkMathAnswer() {
        if let val = Int(userAnswer.trimmingCharacters(in: .whitespaces)), val == mathAnswer {
            store.dismissCurrentlyRinging()
        } else {
            mathError = true
        }
    }
}

// MARK: - Secondary Display Companion View

public struct FullScreenSecondaryView: View {
    public let alarm: AlarmItem
    @ObservedObject private var store = AlarmStore.shared
    
    public init(alarm: AlarmItem) {
        self.alarm = alarm
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            RadialGradient(
                colors: [Color.red.opacity(0.2), Color.black],
                center: .center,
                startRadius: 100,
                endRadius: 800
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.red)
                
                Text(formattedCurrentTime)
                    .font(.system(size: 80, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                
                Text(alarm.title.isEmpty ? "ALARM ACTIVE" : alarm.title.uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                
                Text("Please interact with the primary display to Snooze or Dismiss")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var formattedCurrentTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: store.currentTime)
    }
}

@MainActor
final class HoldDismissState: ObservableObject {
    @Published var progress: CGFloat = 0.0
    @Published var isHolding: Bool = false
    private var timer: Timer?
    
    func startHold(onComplete: @escaping @MainActor () -> Void) {
        cancelHold()
        isHolding = true
        progress = 0.0
        let interval = 0.05
        let total = 3.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isHolding else { return }
                self.progress += CGFloat(interval / total)
                if self.progress >= 1.0 {
                    self.cancelHold()
                    onComplete()
                }
            }
        }
    }
    
    func cancelHold() {
        timer?.invalidate()
        timer = nil
        progress = 0.0
        isHolding = false
    }
}
