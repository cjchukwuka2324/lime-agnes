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
    
    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private let updateInterval: TimeInterval = 0.05 // ~20 updates per second
    
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
        print("🎤 Starting recording...")
        
        // Check if running on simulator (recording doesn't work on simulator)
        #if targetEnvironment(simulator)
        print("⚠️ Running on iOS Simulator - microphone recording is not supported")
        throw NSError(
            domain: "VoiceRecorder",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Voice recording is not available on iOS Simulator. Please test on a physical device."]
        )
        #endif
        
        // Request permission if needed
        let hasPermission = await requestPermission()
        guard hasPermission else {
            print("❌ Microphone permission denied")
            throw NSError(
                domain: "VoiceRecorder",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied. Please enable microphone access in Settings."]
            )
        }
        print("✅ Microphone permission granted")
        
        // Stop any existing recording first
        if isRecording {
            print("⚠️ Stopping existing recording...")
            stopRecording()
            // Give it a moment to fully stop
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        // CRITICAL: Pause AudioPlayerViewModel if it's playing
        // This prevents audio session conflicts
        if let audioPlayer = try? await getAudioPlayerIfPlaying() {
            print("⚠️ AudioPlayerViewModel is currently playing")
            print("   Pausing it to avoid audio session conflict...")
            audioPlayer.pause()
            // Wait for audio player to release the session
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            print("✅ AudioPlayerViewModel paused")
        }
        
        // Post notification to pause any other audio playback
        NotificationCenter.default.post(name: NSNotification.Name("VoiceRecorderWillStart"), object: nil)
        
        // Wait a moment for other components to respond
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Setup audio session (we're already on main thread since class is @MainActor)
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            print("🔧 Setting up audio session...")
            print("📊 Current state - category: \(audioSession.category.rawValue), isOtherAudioPlaying: \(audioSession.isOtherAudioPlaying)")
            
            // First, deactivate any existing session
            do {
                print("🔄 Deactivating existing session...")
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("✅ Deactivated existing session")
            } catch {
                print("⚠️ Could not deactivate (may not be active): \(error.localizedDescription)")
            }
            
            // Wait a moment for deactivation to complete
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Set category BEFORE activating
            print("🎵 Setting audio category to .record...")
            try audioSession.setCategory(.record, mode: .default, options: [])
            print("✅ Audio session category set")
            
            // Activate the session
            print("🔌 Activating audio session...")
            try audioSession.setActive(true)
            print("✅ Audio session activated successfully")
            
        } catch {
            print("❌ Audio session setup error: \(error.localizedDescription)")
            print("❌ Error code: \((error as NSError).code)")
            print("❌ Error domain: \((error as NSError).domain)")
            print("❌ Full error: \(error)")
            
            // Try a more aggressive fallback: use .playAndRecord which is more compatible
            do {
                print("🔄 Trying fallback with .playAndRecord category...")
                // Force deactivate
                try? audioSession.setActive(false, options: [])
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Try .playAndRecord which is more compatible with other audio
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try audioSession.setActive(true)
                print("✅ Fallback with .playAndRecord succeeded")
            } catch let fallbackError {
                print("❌ Fallback also failed: \(fallbackError.localizedDescription)")
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
        print("📁 Recording file path: \(audioFilename.path)")
        
        // Remove file if it exists
        if FileManager.default.fileExists(atPath: audioFilename.path) {
            print("⚠️ Removing existing file...")
            try? FileManager.default.removeItem(at: audioFilename)
        }
        
        // Audio settings - simplified for better compatibility
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        print("🎵 Audio settings: \(settings)")
        
        // Create recorder
        do {
            print("🎙️ Creating AVAudioRecorder...")
            let recorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            print("✅ AVAudioRecorder created")
            
            // Prepare to record (this validates settings and creates the file)
            print("🔧 Preparing to record...")
            let prepared = recorder.prepareToRecord()
            print("📊 prepareToRecord() returned: \(prepared)")
            
            guard prepared else {
                print("❌ prepareToRecord() returned false")
                // Check if file was created
                let fileExists = FileManager.default.fileExists(atPath: audioFilename.path)
                print("📁 File exists after prepare: \(fileExists)")
                
                throw NSError(
                    domain: "VoiceRecorder",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to prepare recorder. Check audio settings and permissions."]
                )
            }
            
            audioRecorder = recorder
            print("✅ Recorder prepared and stored")
            
            // Start recording
            print("▶️ Starting recording...")
            let started = recorder.record()
            print("📊 record() returned: \(started)")
            
            guard started else {
                print("❌ record() returned false")
                // Check for common issues
                let sessionActive = audioSession.isOtherAudioPlaying
                let category = audioSession.category.rawValue
                let isActive = audioSession.isOtherAudioPlaying
                print("🔍 Audio session state - category: \(category), other audio playing: \(sessionActive), isActive: \(isActive)")
                
                let errorMsg = sessionActive
                    ? "Another app is using the microphone. Please close it and try again."
                    : "Failed to start recording. Please check microphone permissions in Settings."
                
                throw NSError(
                    domain: "VoiceRecorder",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: errorMsg]
                )
            }
            
            print("✅ Recording started successfully!")
            isRecording = true
            meterLevel = 0.0
            errorMessage = nil
            recordingURL = nil
            
            // Start meter updates
            startMeterUpdates()
            print("✅ Meter updates started")
        } catch {
            print("❌ Recorder creation/start error: \(error.localizedDescription)")
            print("❌ Full error: \(error)")
            try? audioSession.setActive(false)
            throw error
        }
    }
    
    // MARK: - Stop Recording
    
    func stopRecording() {
        print("🛑 Stopping recording...")
        audioRecorder?.stop()
        stopMeterUpdates()
        
        // Deactivate audio session with notification option
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            print("✅ Audio session deactivated after recording")
        } catch {
            print("❌ Failed to deactivate audio session: \(error)")
        }
        
        if let recorder = audioRecorder {
            recordingURL = recorder.url
            print("📁 Recording saved to: \(recorder.url.lastPathComponent)")
        }
        
        isRecording = false
        meterLevel = 0.0
        audioRecorder = nil
    }
    
    // MARK: - Meter Updates
    
    private func startMeterUpdates() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, self.isRecording else { return }
            
            recorder.updateMeters()
            let level = recorder.averagePower(forChannel: 0)
            
            // Convert dB to 0-1 range
            // dB range is typically -160 to 0, normalize to 0-1
            let normalizedLevel = max(0.0, min(1.0, (level + 60) / 60))
            self.meterLevel = CGFloat(normalizedLevel)
        }
    }
    
    private func stopMeterUpdates() {
        meterTimer?.invalidate()
        meterTimer = nil
        meterLevel = 0.0
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

