import Foundation
@preconcurrency import AVFoundation
import AppKit

@MainActor
public final class AudioEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = AudioEngine()
    
    @Published public private(set) var isRinging: Bool = false
    @Published public private(set) var currentAudioLevel: Float = 0.0
    @Published public private(set) var spectrumLevels: [CGFloat] = Array(repeating: 0.1, count: 20)
    
    private var audioPlayer: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speechTimer: Timer?
    private var meterTimer: Timer?
    
    private var previousSystemVolume: Int?
    private var activeAlarm: AlarmItem?
    private var speechCycleCount = 0
    
    override private init() {
        super.init()
        speechSynthesizer.delegate = self
    }
    
    // MARK: - Volume Management
    
    private func getSystemVolume() -> Int? {
        let script = "output volume of (get volume settings)"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let result = appleScript.executeAndReturnError(&error)
            if error == nil {
                return Int(result.int32Value)
            }
        }
        return nil
    }
    
    private func setSystemVolume(_ volume: Int) {
        let script = "set volume output volume \(volume)"
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
        // Also unmute
        let unmuteScript = "set volume without output muted"
        if let appleScript = NSAppleScript(source: unmuteScript) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
    
    // MARK: - Alarm Trigger
    
    public func startRinging(for alarm: AlarmItem) {
        stopRinging()
        
        self.activeAlarm = alarm
        self.isRinging = true
        self.speechCycleCount = 0
        
        // 1. Max Volume Blast
        if alarm.volumeBlast {
            self.previousSystemVolume = getSystemVolume()
            setSystemVolume(100)
        }
        
        // 2. Play Alarm Sound Loop
        playTone(soundType: alarm.soundType)
        
        // 3. Start "Singing" / Voice Announcements
        if alarm.singVoiceEnabled {
            scheduleSingingAnnouncements(for: alarm)
        }
        
        // 4. Start Spectrum Metering for visualizer
        startMetering()
    }
    
    public func stopRinging() {
        isRinging = false
        
        meterTimer?.invalidate()
        meterTimer = nil
        
        speechTimer?.invalidate()
        speechTimer = nil
        
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Restore previous volume if it was modified
        if let prevVolume = previousSystemVolume {
            setSystemVolume(prevVolume)
            previousSystemVolume = nil
        }
        
        activeAlarm = nil
        currentAudioLevel = 0.0
        spectrumLevels = Array(repeating: 0.1, count: 20)
    }
    
    // MARK: - Audio Tone Playback
    
    public func previewSound(_ soundType: SoundType) {
        stopRinging()
        playTone(soundType: soundType, preview: true)
        startMetering()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            Task { @MainActor in
                if self?.activeAlarm == nil {
                    self?.stopRinging()
                }
            }
        }
    }
    
    private func playTone(soundType: SoundType, preview: Bool = false) {
        guard let data = WaveformGenerator.generateWav(for: soundType) else { return }
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.isMeteringEnabled = true
            audioPlayer?.numberOfLoops = preview ? 2 : -1
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Failed to initialize audio player: \(error)")
        }
    }
    
    // MARK: - "Singing" Engine (Voice Announcements)
    
    private func scheduleSingingAnnouncements(for alarm: AlarmItem) {
        // Initial speech after 1.2 seconds of ringing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isRinging else { return }
                self.speakAlarmDescription(alarm)
            }
        }
        
        // Repeat speech every 10 seconds
        speechTimer = Timer.scheduledTimer(withTimeInterval: 9.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRinging else { return }
                self.speakAlarmDescription(alarm)
            }
        }
    }
    
    private func speakAlarmDescription(_ alarm: AlarmItem) {
        guard !speechSynthesizer.isSpeaking else { return }
        
        speechCycleCount += 1
        
        let timeString = alarm.formattedTime
        let title = alarm.title.isEmpty ? "Wake Up!" : alarm.title
        let desc = alarm.description.isEmpty ? "It is time to rise and start your day!" : alarm.description
        
        let message: String
        if speechCycleCount == 1 {
            message = "Alarm ringing! Time is \(timeString). \(title). \(desc)."
        } else if speechCycleCount % 2 == 0 {
            message = "Attention! \(title). \(desc). Wake up right now!"
        } else {
            message = "Alarm! It is \(timeString). \(desc)."
        }
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.50
        utterance.pitchMultiplier = 1.15
        utterance.volume = 1.0
        
        // Prefer enhanced voice if available
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        // Lower tone volume slightly while speaking so the speech is crystal clear
        audioPlayer?.setVolume(0.35, fadeDuration: 0.3)
        speechSynthesizer.speak(utterance)
    }
    
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.isRinging {
                self.audioPlayer?.setVolume(1.0, fadeDuration: 0.4)
            }
        }
    }
    
    // MARK: - Metering / Audio Spectrum
    
    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer, player.isPlaying else { return }
                player.updateMeters()
                
                let power = player.averagePower(forChannel: 0) // -160 dB to 0 dB
                let normalized = max(0.05, min(1.0, (power + 50.0) / 50.0))
                self.currentAudioLevel = normalized
                
                // Generate simulated reactive spectrum bars
                var newSpectrum: [CGFloat] = []
                for i in 0..<20 {
                    let wave = sin(Double(i) * 0.4 + Date().timeIntervalSince1970 * 8.0)
                    let noise = Double.random(in: 0.8...1.2)
                    let barVal = CGFloat(normalized) * CGFloat(0.4 + 0.6 * abs(wave) * noise)
                    newSpectrum.append(min(1.0, max(0.08, barVal)))
                }
                self.spectrumLevels = newSpectrum
            }
        }
    }
}

// MARK: - Waveform Generator

public struct WaveformGenerator: Sendable {
    public static func generateWav(for soundType: SoundType) -> Data? {
        let sampleRate: Double = 44100.0
        let duration: Double
        
        switch soundType {
        case .digitalBeep:
            duration = 1.2
        case .twinBell:
            duration = 1.5
        case .emergencySiren:
            duration = 1.6
        case .harmoniousWake:
            duration = 2.4
        }
        
        let totalSamples = Int(sampleRate * duration)
        var samples = [Int16](repeating: 0, count: totalSamples)
        
        switch soundType {
        case .digitalBeep:
            // 4 fast burst beeps: 0.08s on, 0.04s off, 0.08s on, 0.04s off, etc.
            let beepLen = Int(sampleRate * 0.08)
            let pauseLen = Int(sampleRate * 0.04)
            let freq1: Double = 2200.0
            let freq2: Double = 2750.0
            
            for b in 0..<4 {
                let start = b * (beepLen + pauseLen)
                for i in 0..<beepLen {
                    let idx = start + i
                    guard idx < totalSamples else { break }
                    let t = Double(i) / sampleRate
                    // Dual high-frequency square/sine blend
                    let val = (sin(2.0 * .pi * freq1 * t) * 0.6 + sin(2.0 * .pi * freq2 * t) * 0.4)
                    let envelope = min(1.0, Double(i) / 200.0) * min(1.0, Double(beepLen - i) / 200.0)
                    samples[idx] = Int16(clamping: Int(val * envelope * 32000.0))
                }
            }
            
        case .twinBell:
            // Dual metallic hammer strikes at 10 strikes/second
            let strikes = 12
            let strikeInterval = Int(sampleRate * 0.11)
            let freqA: Double = 1050.0
            let freqB: Double = 1320.0
            
            for s in 0..<strikes {
                let start = s * strikeInterval
                let freq = (s % 2 == 0) ? freqA : freqB
                for i in 0..<strikeInterval {
                    let idx = start + i
                    guard idx < totalSamples else { break }
                    let t = Double(i) / sampleRate
                    // Exponential decay
                    let decay = exp(-t * 28.0)
                    let tone = sin(2.0 * .pi * freq * t) + 0.4 * sin(2.0 * .pi * (freq * 2.76) * t)
                    samples[idx] = Int16(clamping: Int(tone * decay * 31000.0))
                }
            }
            
        case .emergencySiren:
            // Pitch sweeps from 700Hz to 1500Hz
            for i in 0..<totalSamples {
                let t = Double(i) / sampleRate
                let cycleProgress = (t.truncatingRemainder(dividingBy: 0.8)) / 0.8
                let freq = 750.0 + 750.0 * (cycleProgress < 0.5 ? (cycleProgress * 2.0) : ((1.0 - cycleProgress) * 2.0))
                let phase = 2.0 * .pi * freq * t
                // Harmonic distortion for siren bite
                let sampleVal = sin(phase) + 0.3 * sin(phase * 3.0)
                samples[i] = Int16(clamping: Int(sampleVal * 29000.0))
            }
            
        case .harmoniousWake:
            // Chord arpeggio: C5 (523Hz), E5 (659Hz), G5 (784Hz), C6 (1046Hz)
            let notes: [Double] = [523.25, 659.25, 783.99, 1046.50]
            let noteDuration = Int(sampleRate * 0.4)
            for (nIdx, freq) in notes.enumerated() {
                let start = nIdx * noteDuration
                for i in 0..<(totalSamples - start) {
                    let idx = start + i
                    guard idx < totalSamples else { break }
                    let t = Double(i) / sampleRate
                    let decay = exp(-t * 3.5)
                    let tone = sin(2.0 * .pi * freq * t) + 0.3 * sin(2.0 * .pi * freq * 2.0 * t)
                    let currentVal = Double(samples[idx]) / 32000.0
                    let combined = currentVal + (tone * decay * 0.7)
                    samples[idx] = Int16(clamping: Int(combined * 30000.0))
                }
            }
        }
        
        return buildWavData(samples: samples, sampleRate: Int(sampleRate))
    }
    
    private static func buildWavData(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let subChunk2Size: UInt32 = UInt32(samples.count * 2)
        let chunkSize: UInt32 = 36 + subChunk2Size
        
        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        data.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        
        // fmt sub-chunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        let subchunk1Size: UInt32 = 16
        data.append(contentsOf: withUnsafeBytes(of: subchunk1Size.littleEndian) { Array($0) })
        let audioFormat: UInt16 = 1 // PCM
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        let sRate = UInt32(sampleRate)
        data.append(contentsOf: withUnsafeBytes(of: sRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data sub-chunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        data.append(contentsOf: withUnsafeBytes(of: subChunk2Size.littleEndian) { Array($0) })
        
        // Samples
        samples.withUnsafeBufferPointer { buffer in
            data.append(buffer)
        }
        
        return data
    }
}
