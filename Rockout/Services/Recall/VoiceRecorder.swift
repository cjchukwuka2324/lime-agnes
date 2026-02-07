import Foundation
import AVFoundation
import Combine

// Forward declaration to avoid circular dependency
@MainActor
protocol AudioPlayerPausable {
    var isPlaying: Bool { get }
    func pause()
}

@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var meterLevel: CGFloat = 0.0
    @Published var recordingURL: URL?
    @Published var errorMessage: String?
    @Published var silenceDetected: Bool = false
    
    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var silenceTimer: Timer?
    private let updateInterval: TimeInterval = 0.05 // ~20 updates per second
    private let silenceThreshold: Float = -40.0 // dB threshold for silence
    private let silenceDuration: TimeInterval = 2.5 // seconds of silence before auto-stop
    private var lastSoundTime: Date = Date()
    
    override init() {
        super.init()
    }
    
    // MARK: - Audio Player Check
    
    private func getAudioPlayerIfPlaying() async throws -> AudioPlayerPausable? {
        // Try to get AudioPlayerViewModel.shared
        // Using dynamic lookup to avoid circular dependency
        guard let audioPlayerClass = NSClassFromString("Rockout.AudioPlayerViewModel") as? NSObject.Type,
              let shared = audioPlayerClass.value(forKey: "shared") as? NSObject,
              let isPlaying = shared.value(forKey: "isPlaying") as? Bool,
              isPlaying else {
            return nil
        }
        
        // Create a wrapper that conforms to our protocol
        return AudioPlayerWrapper(instance: shared)
    }
    
    // MARK: - Request Permission
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - Start Recording
    
    func startRecording() async throws {
        let requestId = UUID().uuidString.prefix(8)
        let startTime = Date()
        
        print("🎤 [VOICE-RECORDER] [\(requestId)] startRecording() called")
        
        // Check if running on simulator (recording doesn't work on simulator)
        #if targetEnvironment(simulator)
        print("⚠️ [VOICE-RECORDER] [\(requestId)] Running on iOS Simulator - microphone recording is not supported")
        throw NSError(
            domain: "VoiceRecorder",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Voice recording is not available on iOS Simulator. Please test on a physical device."]
        )
        #endif
        
        // Request permission if needed
        let permissionStartTime = Date()
        let hasPermission = await requestPermission()
        let permissionDuration = Date().timeIntervalSince(permissionStartTime)
        guard hasPermission else {
            print("❌ [VOICE-RECORDER] [\(requestId)] Microphone permission denied after \(String(format: "%.3f", permissionDuration))s")
            throw NSError(
                domain: "VoiceRecorder",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied. Please enable microphone access in Settings."]
            )
        }
        print("✅ [VOICE-RECORDER] [\(requestId)] Microphone permission granted in \(String(format: "%.3f", permissionDuration))s")
        
        // Stop any existing recording first
        if isRecording {
            print("⚠️ [VOICE-RECORDER] [\(requestId)] Stopping existing recording...")
            stopRecording()
            // Give it a moment to fully stop
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // CRITICAL: Pause AudioPlayerViewModel if it's playing
        // This prevents audio session conflicts
        if let audioPlayer = try? await getAudioPlayerIfPlaying() {
            print("⚠️ [VOICE-RECORDER] [\(requestId)] AudioPlayerViewModel is currently playing")
            print("   Pausing it to avoid audio session conflict...")
            audioPlayer.pause()
            // Wait for audio player to release the session
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            print("✅ [VOICE-RECORDER] [\(requestId)] AudioPlayerViewModel paused")
        }
        
        // Post notification to pause any other audio playback
        NotificationCenter.default.post(name: NSNotification.Name("VoiceRecorderWillStart"), object: nil)
        
        // Wait a moment for other components to respond
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Setup audio session (we're already on main thread since class is @MainActor)
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            let sessionSetupStartTime = Date()
            print("🔧 [VOICE-RECORDER] [\(requestId)] Setting up audio session...")
            print("📊 [VOICE-RECORDER] [\(requestId)] Current state - category: \(audioSession.category.rawValue), isOtherAudioPlaying: \(audioSession.isOtherAudioPlaying)")
            
            // First, deactivate any existing session
            do {
                print("🔄 [VOICE-RECORDER] [\(requestId)] Deactivating existing session...")
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("✅ [VOICE-RECORDER] [\(requestId)] Deactivated existing session")
            } catch {
                print("⚠️ [VOICE-RECORDER] [\(requestId)] Could not deactivate (may not be active): \(error.localizedDescription)")
            }
            
            // Wait a moment for deactivation to complete
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Set category BEFORE activating
            print("🎵 [VOICE-RECORDER] [\(requestId)] Setting audio category to .record...")
            try audioSession.setCategory(.record, mode: .default, options: [])
            print("✅ [VOICE-RECORDER] [\(requestId)] Audio session category set")
            
            // Activate the session
            print("🔌 [VOICE-RECORDER] [\(requestId)] Activating audio session...")
            try audioSession.setActive(true)
            let sessionSetupDuration = Date().timeIntervalSince(sessionSetupStartTime)
            print("✅ [VOICE-RECORDER] [\(requestId)] Audio session activated successfully in \(String(format: "%.3f", sessionSetupDuration))s")
            
        } catch {
            print("❌ [VOICE-RECORDER] [\(requestId)] Audio session setup error: \(error.localizedDescription)")
            print("   Error code: \((error as NSError).code)")
            print("   Error domain: \((error as NSError).domain)")
            print("   Full error: \(error)")
            
            // Try a more aggressive fallback: use .playAndRecord which is more compatible
            do {
                print("🔄 [VOICE-RECORDER] [\(requestId)] Trying fallback with .playAndRecord category...")
                // Force deactivate
                try? audioSession.setActive(false, options: [])
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Try .playAndRecord which is more compatible with other audio
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try audioSession.setActive(true)
                print("✅ [VOICE-RECORDER] [\(requestId)] Fallback with .playAndRecord succeeded")
            } catch let fallbackError {
                print("❌ [VOICE-RECORDER] [\(requestId)] Fallback also failed: \(fallbackError.localizedDescription)")
                throw NSError(
                    domain: "VoiceRecorder",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to setup audio session: \(error.localizedDescription). Please close other audio apps (including music players) and try again."]
                )
            }
        }
        
        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recall_recording_\(UUID().uuidString).m4a")
        print("📁 [VOICE-RECORDER] [\(requestId)] Recording file path: \(audioFilename.path)")
        
        // Remove file if it exists
        if FileManager.default.fileExists(atPath: audioFilename.path) {
            print("⚠️ [VOICE-RECORDER] [\(requestId)] Removing existing file...")
            try? FileManager.default.removeItem(at: audioFilename)
        }
        
        // Audio settings - simplified for better compatibility
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        print("🎵 [VOICE-RECORDER] [\(requestId)] Audio settings: \(settings)")
        
        // Create recorder
        do {
            let recorderStartTime = Date()
            print("🎙️ [VOICE-RECORDER] [\(requestId)] Creating AVAudioRecorder...")
            let recorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            print("✅ [VOICE-RECORDER] [\(requestId)] AVAudioRecorder created")
            
            // Prepare to record (this validates settings and creates the file)
            print("🔧 [VOICE-RECORDER] [\(requestId)] Preparing to record...")
            let prepared = recorder.prepareToRecord()
            print("📊 [VOICE-RECORDER] [\(requestId)] prepareToRecord() returned: \(prepared)")
            
            guard prepared else {
                print("❌ [VOICE-RECORDER] [\(requestId)] prepareToRecord() returned false")
                // Check if file was created
                let fileExists = FileManager.default.fileExists(atPath: audioFilename.path)
                print("📁 [VOICE-RECORDER] [\(requestId)] File exists after prepare: \(fileExists)")
                
                throw NSError(
                    domain: "VoiceRecorder",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to prepare recorder. Check audio settings and permissions."]
                )
            }
            
            audioRecorder = recorder
            print("✅ [VOICE-RECORDER] [\(requestId)] Recorder prepared and stored")
            
            // Start recording
            print("▶️ [VOICE-RECORDER] [\(requestId)] Starting recording...")
            let started = recorder.record()
            print("📊 [VOICE-RECORDER] [\(requestId)] record() returned: \(started)")
            
            guard started else {
                print("❌ [VOICE-RECORDER] [\(requestId)] record() returned false")
                // Check for common issues
                let sessionActive = audioSession.isOtherAudioPlaying
                let category = audioSession.category.rawValue
                let isActive = audioSession.isOtherAudioPlaying
                print("🔍 [VOICE-RECORDER] [\(requestId)] Audio session state - category: \(category), other audio playing: \(sessionActive), isActive: \(isActive)")
                
                let errorMsg = sessionActive
                    ? "Another app is using the microphone. Please close it and try again."
                    : "Failed to start recording. Please check microphone permissions in Settings."
                
                throw NSError(
                    domain: "VoiceRecorder",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: errorMsg]
                )
            }
            
            let totalDuration = Date().timeIntervalSince(startTime)
            print("✅ [VOICE-RECORDER] [\(requestId)] Recording started successfully in \(String(format: "%.3f", totalDuration))s!")
            isRecording = true
            meterLevel = 0.0
            errorMessage = nil
            recordingURL = nil
            
            // Start meter updates
            startMeterUpdates()
            print("✅ [VOICE-RECORDER] [\(requestId)] Meter updates started")
        } catch {
            let totalDuration = Date().timeIntervalSince(startTime)
            print("❌ [VOICE-RECORDER] [\(requestId)] Recorder creation/start error after \(String(format: "%.3f", totalDuration))s: \(error.localizedDescription)")
            print("   Full error: \(error)")
            try? audioSession.setActive(false)
            throw error
        }
    }
    
    // MARK: - Stop Recording
    
    func stopRecording() {
        let requestId = UUID().uuidString.prefix(8)
        let startTime = Date()
        
        print("🛑 [VOICE-RECORDER] [\(requestId)] stopRecording() called")
        print("📊 [VOICE-RECORDER] [\(requestId)] Current state: isRecording=\(isRecording), hasRecorder=\(audioRecorder != nil)")
        
        // Set isRecording to false FIRST, before any async operations
        // This ensures state is immediately updated
        isRecording = false
        meterLevel = 0.0
        
        // Stop recorder and meter updates
        audioRecorder?.stop()
        stopMeterUpdates()
        
        // Save recording URL before clearing recorder
        if let recorder = audioRecorder {
            recordingURL = recorder.url
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: recorder.url.path)[.size] as? Int64) ?? 0
            print("📁 [VOICE-RECORDER] [\(requestId)] Recording saved to: \(recorder.url.lastPathComponent), size: \(fileSize) bytes")
        }
        
        // Clear recorder reference
        audioRecorder = nil
        
        // Deactivate audio session with notification option
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            let duration = Date().timeIntervalSince(startTime)
            print("✅ [VOICE-RECORDER] [\(requestId)] Audio session deactivated after recording in \(String(format: "%.3f", duration))s")
        } catch {
            print("❌ [VOICE-RECORDER] [\(requestId)] Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Meter Updates
    
    private func startMeterUpdates() {
        lastSoundTime = Date()
        silenceDetected = false
        
        meterTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, self.isRecording else { return }
            
            recorder.updateMeters()
            let level = recorder.averagePower(forChannel: 0)
            
            // Convert dB to 0-1 range
            // dB range is typically -160 to 0, normalize to 0-1
            let normalizedLevel = max(0.0, min(1.0, (level + 60) / 60))
            self.meterLevel = CGFloat(normalizedLevel)
            
            // Check for silence
            if level > self.silenceThreshold {
                // Sound detected, update last sound time
                self.lastSoundTime = Date()
                self.silenceDetected = false
            } else {
                // Check if we've been silent for the threshold duration
                let silenceElapsed = Date().timeIntervalSince(self.lastSoundTime)
                if silenceElapsed >= self.silenceDuration {
                    self.silenceDetected = true
                }
            }
        }
        
        // Start silence detection timer
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            
            let silenceElapsed = Date().timeIntervalSince(self.lastSoundTime)
            if silenceElapsed >= self.silenceDuration {
                self.silenceDetected = true
                // Auto-stop after silence
                self.stopRecording()
            }
        }
    }
    
    private func stopMeterUpdates() {
        meterTimer?.invalidate()
        meterTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        meterLevel = 0.0
        silenceDetected = false
    }
}

// MARK: - AudioPlayerWrapper

private class AudioPlayerWrapper: AudioPlayerPausable {
    private let instance: NSObject
    
    init(instance: NSObject) {
        self.instance = instance
    }
    
    var isPlaying: Bool {
        instance.value(forKey: "isPlaying") as? Bool ?? false
    }
    
    func pause() {
        instance.perform(Selector(("pause")))
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if !flag {
                errorMessage = "Recording finished unsuccessfully"
            }
            isRecording = false
            stopMeterUpdates()
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            errorMessage = error?.localizedDescription ?? "Recording error occurred"
            isRecording = false
            stopMeterUpdates()
        }
    }
}

