import Foundation
import AVFoundation
import Combine

/// Centralized audio session management for Recall feature
/// Handles AVAudioSession configuration, interruptions, route changes, and permissions
@MainActor
final class AudioSessionManager: NSObject, ObservableObject {
    static let shared = AudioSessionManager()
    
    @Published var isReady: Bool = false
    @Published var hasMicrophonePermission: Bool = false
    @Published var hasSpeechRecognitionPermission: Bool = false
    @Published var isInterrupted: Bool = false
    @Published var currentRoute: AVAudioSessionRouteDescription?
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        super.init()
        setupNotifications()
        checkPermissions()
    }
    
    // MARK: - Permission Checks
    
    func checkPermissions() {
        checkMicrophonePermission()
        checkSpeechRecognitionPermission()
        updateReadyState()
    }
    
    private func checkMicrophonePermission() {
        switch audioSession.recordPermission {
        case .granted:
            hasMicrophonePermission = true
        case .denied, .undetermined:
            hasMicrophonePermission = false
        @unknown default:
            hasMicrophonePermission = false
        }
    }
    
    private func checkSpeechRecognitionPermission() {
        // SFSpeechRecognizer authorization is checked separately
        // This is a placeholder - actual check happens in SpeechTranscriber
        hasSpeechRecognitionPermission = false
    }
    
    func requestMicrophonePermission() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        hasMicrophonePermission = granted
        updateReadyState()
        return granted
    }
    
    // MARK: - Audio Session Configuration
    
    func configureForRecording() throws {
        try audioSession.setCategory(.record, mode: .default, options: [])
        try audioSession.setActive(true)
        currentRoute = audioSession.currentRoute
        updateReadyState()
    }
    
    func configureForPlayback() throws {
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
        currentRoute = audioSession.currentRoute
        updateReadyState()
    }
    
    func configureForSpeechRecognition() throws {
        // Use .playAndRecord for speech recognition to allow both input and output
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true)
        currentRoute = audioSession.currentRoute
        updateReadyState()
    }
    
    func deactivate() throws {
        try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        updateReadyState()
    }
    
    // MARK: - State Management
    
    private func updateReadyState() {
        isReady = hasMicrophonePermission && !isInterrupted
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        // Audio session interruptions
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                self?.handleInterruption(notification)
            }
            .store(in: &cancellables)
        
        // Route changes (e.g., AirPods connected)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                self?.handleRouteChange(notification)
            }
            .store(in: &cancellables)
        
        // Media services reset
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in
                self?.handleMediaServicesReset()
            }
            .store(in: &cancellables)
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            isInterrupted = true
            updateReadyState()
            Logger.recall.warning("Audio session interrupted")
        case .ended:
            isInterrupted = false
            updateReadyState()
            
            // Try to reactivate if we have an options value
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    do {
                        try audioSession.setActive(true)
                        Logger.recall.success("Audio session resumed after interruption")
                    } catch {
                        Logger.recall.error("Failed to resume audio session: \(error.localizedDescription)")
                    }
                }
            }
        @unknown default:
            break
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        currentRoute = audioSession.currentRoute
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            Logger.recall.info("Audio route changed: \(reason == .newDeviceAvailable ? "new device" : "device removed")")
        case .categoryChange:
            Logger.recall.info("Audio route changed due to category change")
        default:
            break
        }
    }
    
    private func handleMediaServicesReset() {
        Logger.recall.warning("Media services were reset - reconfiguring audio session")
        // Re-check permissions and reconfigure if needed
        checkPermissions()
    }
}

