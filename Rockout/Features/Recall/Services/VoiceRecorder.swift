import Foundation
import AVFoundation
import Combine
import UIKit

@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var meterLevel: CGFloat = 0.0
    @Published var recordingURL: URL?
    @Published var errorMessage: String?
    
    private var audioRecorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private let updateInterval: TimeInterval = 0.05 // ~20 updates per second
    private var interruptionObserver: NSObjectProtocol?
    
    override init() {
        super.init()
        setupInterruptionObserver()
    }
    
    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Interruption Handling
    
    private func setupInterruptionObserver() {
        // Observe interruptions
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            if let userInfo = notification.userInfo,
               let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
               let type = AVAudioSession.InterruptionType(rawValue: typeValue) {
                switch type {
                case .began:
                    print("⚠️ Audio session interruption began")
                    if self.isRecording {
                        self.stopRecording()
                    }
                case .ended:
                    print("✅ Audio session interruption ended")
                    if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                        if options.contains(.shouldResume) {
                            print("   Should resume recording")
                        }
                    }
                @unknown default:
                    break
                }
            }
        }
        
        // Also observe route changes - this helps detect when audio becomes available
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
               let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) {
                print("📡 Audio route changed: \(reason.rawValue)")
                switch reason {
                case .newDeviceAvailable:
                    print("   New audio device available")
                case .oldDeviceUnavailable:
                    print("   Audio device unavailable")
                case .categoryChange:
                    print("   Category changed")
                default:
                    break
                }
            }
        }
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
        
        // Setup audio session
        let audioSession = AVAudioSession.sharedInstance()
        
        // CRITICAL: Check and pause AudioPlayerViewModel if it's playing
        // AudioPlayerViewModel uses .playback category which conflicts with .record
        let audioPlayer = AudioPlayerViewModel.shared
        if audioPlayer.isPlaying {
            print("⚠️ AudioPlayerViewModel is currently playing")
            print("   Pausing it to avoid audio session conflict...")
            audioPlayer.pause()
            // Wait a moment for it to release the session
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            print("✅ AudioPlayerViewModel paused")
        }
        
        // #region agent log
        do {
            let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
            let logData = """
            {"sessionId":"debug-session","runId":"run5","hypothesisId":"A","location":"VoiceRecorder.swift:67","message":"Audio session setup start","data":{"category":\(audioSession.category.rawValue),"isOtherAudioPlaying":\(audioSession.isOtherAudioPlaying),"audioPlayerWasPlaying":\(audioPlayer.isPlaying)},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
            """
            let fileURL = URL(fileURLWithPath: logPath)
            if let data = (logData + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logPath) {
                    if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        } catch {}
        // #endregion
        
        // PostComposerView's startRecording() is SYNCHRONOUS and called directly from button
        // We're async, but let's ensure audio session setup happens synchronously on main thread
        // This matches PostComposerView's execution model more closely
        
        // #region agent log
        do {
            let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
            let logData = """
            {"sessionId":"debug-session","runId":"run8","hypothesisId":"H","location":"VoiceRecorder.swift:167","message":"Starting - ensuring main thread sync execution","data":{"isMainThread":\(Thread.isMainThread)},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
            """
            let fileURL = URL(fileURLWithPath: logPath)
            if let data = (logData + "\n").data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logPath) {
                    if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        } catch {}
        // #endregion
        
        // Execute audio session setup synchronously on main thread (like PostComposerView)
        // PostComposerView does this in a synchronous function, so we'll do the same
        try await MainActor.run {
            let audioSession = AVAudioSession.sharedInstance()
            
            // #region agent log
            do {
                let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                let logData = """
                {"sessionId":"debug-session","runId":"run8","hypothesisId":"H","location":"VoiceRecorder.swift:185","message":"In MainActor.run - about to set category","data":{"currentCategory":\(audioSession.category.rawValue),"isMainThread":\(Thread.isMainThread)},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                """
                let fileURL = URL(fileURLWithPath: logPath)
                if let data = (logData + "\n").data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: logPath) {
                        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(data)
                            fileHandle.closeFile()
                        }
                    } else {
                        try? data.write(to: fileURL, options: .atomic)
                    }
                }
            } catch {}
            // #endregion
            
            // EXACT PostComposerView pattern (lines 750-751)
            print("🔧 Setting up audio session (PostComposerView pattern, sync on main thread)...")
            print("🎵 Setting category to .playAndRecord, mode .default (PostComposerView line 750)...")
            try audioSession.setCategory(.playAndRecord, mode: .default)
            print("✅ Category set")
            
            // #region agent log
            do {
                let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                let logData = """
                {"sessionId":"debug-session","runId":"run8","hypothesisId":"H","location":"VoiceRecorder.swift:200","message":"Category set, about to activate","data":{"category":\(audioSession.category.rawValue)},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                """
                let fileURL = URL(fileURLWithPath: logPath)
                if let data = (logData + "\n").data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: logPath) {
                        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(data)
                            fileHandle.closeFile()
                        }
                    } else {
                        try? data.write(to: fileURL, options: .atomic)
                    }
                }
            } catch {}
            // #endregion
            
            print("🔌 Activating audio session (PostComposerView line 751)...")
            try audioSession.setActive(true)
            print("✅ Audio session activated (PostComposerView pattern)")
            
            // #region agent log
            do {
                let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                let logData = """
                {"sessionId":"debug-session","runId":"run8","hypothesisId":"H","location":"VoiceRecorder.swift:220","message":"Activation succeeded - PostComposerView pattern","data":{"category":\(audioSession.category.rawValue)},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                """
                let fileURL = URL(fileURLWithPath: logPath)
                if let data = (logData + "\n").data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: logPath) {
                        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(data)
                            fileHandle.closeFile()
                        }
                    } else {
                        try? data.write(to: fileURL, options: .atomic)
                    }
                }
            } catch {}
            // #endregion
        }
        
        // Get audioSession again for recorder setup (we're still in the do block)
        let audioSession = AVAudioSession.sharedInstance()
            let lastError = error
                let nsError = error as NSError
                print("❌ Minimal activation failed immediately")
                print("   Error code: \(nsError.code)")
                print("   Error domain: \(nsError.domain)")
                print("   Error description: \(error.localizedDescription)")
                print("   Full error: \(error)")
                
                // #region agent log
                do {
                    let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                    let logData = """
                    {"sessionId":"debug-session","runId":"run5","hypothesisId":"E","location":"VoiceRecorder.swift:290","message":"Activation failed immediately","data":{"errorCode":\(nsError.code),"errorDomain":"\(nsError.domain)","errorDescription":"\(error.localizedDescription)"},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                    """
                    let fileURL = URL(fileURLWithPath: logPath)
                    if let data = (logData + "\n").data(using: .utf8) {
                        if FileManager.default.fileExists(atPath: logPath) {
                            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                                fileHandle.seekToEndOfFile()
                                fileHandle.write(data)
                                fileHandle.closeFile()
                            }
                        } else {
                            try? data.write(to: fileURL, options: .atomic)
                        }
                    }
                } catch {}
                // #endregion
                
                // Check if it's the insufficientPriority error
                if nsError.code == 561017449 {
                    print("⚠️ Detected insufficientPriority error (561017449)")
                    print("   This means another audio session has higher priority")
                    print("   Possible causes:")
                    print("   - Active phone call or FaceTime call")
                    print("   - AudioPlayerViewModel still holding session")
                    print("   - System audio event")
                    print("   - Another app using microphone")
                    print("   Attempting retry with progressively longer delays...")
                    
                    // Retry with exponential backoff
                    let maxRetries = 5
                    let baseDelay: UInt64 = 1_000_000_000 // 1 second base delay
                    
                    for attempt in 0..<maxRetries {
                        let delay = baseDelay * UInt64(attempt + 1) // 1s, 2s, 3s, 4s, 5s
                        print("⏳ Waiting \(Double(delay) / 1_000_000_000)s before retry \(attempt + 1)/\(maxRetries)...")
                        try? await Task.sleep(nanoseconds: delay)
                        
                        // Re-check state before retry
                        print("📊 Pre-retry state (attempt \(attempt + 1)):")
                        print("   Category: \(audioSession.category.rawValue)")
                        print("   Other audio playing: \(audioSession.isOtherAudioPlaying)")
                        print("   AudioPlayer playing: \(AudioPlayerViewModel.shared.isPlaying)")
                        
                        do {
                            print("🔄 Retry attempt \(attempt + 1)/\(maxRetries)...")
                            try audioSession.setActive(true)
                            activationSuccess = true
                            print("✅ Audio session activated on retry \(attempt + 1)")
                            break
                        } catch retryError {
                            lastError = retryError
                            let retryNsError = retryError as NSError
                            print("❌ Retry \(attempt + 1) failed: code=\(retryNsError.code)")
                            
                            // #region agent log
                            do {
                                let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                                let logData = """
                                {"sessionId":"debug-session","runId":"run5","hypothesisId":"E","location":"VoiceRecorder.swift:330","message":"Retry failed","data":{"attempt":\(attempt + 1),"errorCode":\(retryNsError.code)},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                                """
                                let fileURL = URL(fileURLWithPath: logPath)
                                if let data = (logData + "\n").data(using: .utf8) {
                                    if FileManager.default.fileExists(atPath: logPath) {
                                        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                                            fileHandle.seekToEndOfFile()
                                            fileHandle.write(data)
                                            fileHandle.closeFile()
                                        }
                                    } else {
                                        try? data.write(to: fileURL, options: .atomic)
                                    }
                                }
                            } catch {}
                            // #endregion
                            
                            if retryNsError.code != 561017449 {
                                // Different error - don't retry
                                print("❌ Error changed to \(retryNsError.code), not retrying")
                                throw retryError
                            }
                            
                            if attempt == maxRetries - 1 {
                                print("❌ All \(maxRetries) retries exhausted")
                                print("   Final error code: \(retryNsError.code)")
                                throw retryError
                            }
                        }
                    }
                } else {
                    // Different error - throw immediately
                    print("❌ Non-retryable error: \(nsError.code), throwing immediately")
                    throw error
                }
            }
            
            guard activationSuccess else {
                let finalError = lastError ?? NSError(domain: "VoiceRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to activate audio session"])
                print("❌ Final activation check failed")
                throw finalError
            }
            
            print("✅ Audio session is now active and ready")
            
            // #region agent log
            do {
                let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                let logData = """
                {"sessionId":"debug-session","runId":"run1","hypothesisId":"A","location":"VoiceRecorder.swift:135","message":"After activation success","data":{"activationSuccess":true},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                """
                let fileURL = URL(fileURLWithPath: logPath)
                if let data = (logData + "\n").data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: logPath) {
                        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(data)
                            fileHandle.closeFile()
                        }
                    } else {
                        try? data.write(to: fileURL, options: .atomic)
                    }
                }
            } catch {}
            // #endregion
            
            // Verify it's active
            if !audioSession.isOtherAudioPlaying {
                print("✅ No other audio playing, session is ready")
            }
        } catch {
            print("❌ Audio session setup error: \(error.localizedDescription)")
            print("❌ Error code: \((error as NSError).code)")
            print("❌ Error domain: \((error as NSError).domain)")
            print("❌ Full error: \(error)")
            
            // #region agent log
            do {
                let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                let nsError = error as NSError
                let logData = """
                {"sessionId":"debug-session","runId":"run1","hypothesisId":"A,B,C,D,E","location":"VoiceRecorder.swift:148","message":"Activation failed","data":{"errorCode":\(nsError.code),"errorDomain":"\(nsError.domain)","errorDescription":"\(error.localizedDescription)"},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                """
                let fileURL = URL(fileURLWithPath: logPath)
                if let data = (logData + "\n").data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: logPath) {
                        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write(data)
                            fileHandle.closeFile()
                        }
                    } else {
                        try? data.write(to: fileURL, options: .atomic)
                    }
                }
            } catch {}
            // #endregion
            
            // Try a fallback: use record category only
            do {
                print("🔄 Trying fallback: record category only...")
                
                // #region agent log
                do {
                    let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                    let logData = """
                    {"sessionId":"debug-session","runId":"run1","hypothesisId":"B","location":"VoiceRecorder.swift:160","message":"Fallback attempt - record category","data":{},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                    """
                    let fileURL = URL(fileURLWithPath: logPath)
                    if let data = (logData + "\n").data(using: .utf8) {
                        if FileManager.default.fileExists(atPath: logPath) {
                            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                                fileHandle.seekToEndOfFile()
                                fileHandle.write(data)
                                fileHandle.closeFile()
                            }
                        } else {
                            try? data.write(to: fileURL, options: .atomic)
                        }
                    }
                } catch {}
                // #endregion
                
                try audioSession.setCategory(.record, mode: .default, options: [])
                try audioSession.setActive(true)
                print("✅ Fallback succeeded")
                
                // #region agent log
                do {
                    let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                    let logData = """
                    {"sessionId":"debug-session","runId":"run1","hypothesisId":"B","location":"VoiceRecorder.swift:170","message":"Fallback succeeded","data":{},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                    """
                    let fileURL = URL(fileURLWithPath: logPath)
                    if let data = (logData + "\n").data(using: .utf8) {
                        if FileManager.default.fileExists(atPath: logPath) {
                            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                                fileHandle.seekToEndOfFile()
                                fileHandle.write(data)
                                fileHandle.closeFile()
                            }
                        } else {
                            try? data.write(to: fileURL, options: .atomic)
                        }
                    }
                } catch {}
                // #endregion
            } catch {
                let fallbackError = error
                print("❌ Fallback also failed: \(fallbackError.localizedDescription)")
                
                // #region agent log
                do {
                    let logPath = "/Users/chukwudiebube/Downloads/RockOut-main/.cursor/debug.log"
                    let nsError = fallbackError as NSError
                    let logData = """
                    {"sessionId":"debug-session","runId":"run1","hypothesisId":"B","location":"VoiceRecorder.swift:180","message":"Fallback failed","data":{"errorCode":\(nsError.code),"errorDescription":"\(fallbackError.localizedDescription)"},"timestamp":\(Int(Date().timeIntervalSince1970 * 1000))}
                    """
                    let fileURL = URL(fileURLWithPath: logPath)
                    if let data = (logData + "\n").data(using: .utf8) {
                        if FileManager.default.fileExists(atPath: logPath) {
                            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                                fileHandle.seekToEndOfFile()
                                fileHandle.write(data)
                                fileHandle.closeFile()
                            }
                        } else {
                            try? data.write(to: fileURL, options: .atomic)
                        }
                    }
                } catch {}
                // #endregion
                
                throw NSError(
                    domain: "VoiceRecorder",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to setup audio session: \(error.localizedDescription). Please close other audio apps and try again."]
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
        audioRecorder?.stop()
        stopMeterUpdates()
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false)
        
        if let recorder = audioRecorder {
            recordingURL = recorder.url
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

