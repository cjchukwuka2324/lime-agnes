import Foundation
import Combine
import UIKit

/// State machine for Recall feature with gate conditions to prevent accidental triggers
/// Ensures safe state transitions and enforces listening gate conditions
@MainActor
final class RecallStateMachine: ObservableObject {
    @Published var currentState: RecallState = .idle
    @Published var lastError: Error?
    
    // Gate condition states
    @Published var isScrolling: Bool = false
    @Published var hasAudioPermission: Bool = false
    @Published var isAudioSessionReady: Bool = false
    @Published var longPressBeganOnOrb: Bool = false
    
    // Cooldown after scrolling stops to prevent accidental activation
    @Published var scrollCooldownActive: Bool = false
    private var scrollCooldownTimer: Timer?
    
    private let audioSessionManager = AudioSessionManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Observe audio session manager state
        audioSessionManager.$isReady
            .assign(to: \.isAudioSessionReady, on: self)
            .store(in: &cancellables)
        
        audioSessionManager.$hasMicrophonePermission
            .assign(to: \.hasAudioPermission, on: self)
            .store(in: &cancellables)
        
        // Check initial permissions
        Task {
            await audioSessionManager.checkPermissions()
        }
    }
    
    // MARK: - State Transitions
    
    func handleEvent(_ event: RecallStateMachineEvent) {
        switch event {
        case .longPressBegan:
            handleLongPressBegan()
        case .longPressEnded:
            handleLongPressEnded()
        case .userTappedStart:
            handleUserTappedStart()
        case .userTappedStop:
            handleUserTappedStop()
        case .wakeWordDetected:
            handleWakeWordDetected()
        case .scrollStarted:
            isScrolling = true
            scrollCooldownActive = true
            // Cancel any existing cooldown timer
            scrollCooldownTimer?.invalidate()
        case .scrollEnded:
            isScrolling = false
            // Start cooldown period after scrolling stops (1.5 seconds to prevent accidental activation)
            scrollCooldownActive = true
            scrollCooldownTimer?.invalidate()
            scrollCooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.scrollCooldownActive = false
                }
            }
            // Ensure timer runs on main run loop
            if let timer = scrollCooldownTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        case .silenceTimeout:
            handleSilenceTimeout()
        case .cancel:
            handleCancel()
        case .responseReceived:
            handleResponseReceived()
        case .error(let error):
            handleError(error)
        }
    }
    
    // MARK: - Gate Conditions
    
    /// Check if all gate conditions are met to enter listening state
    func canEnterListening() -> Bool {
        let conditions = [
            !isScrolling,
            !scrollCooldownActive,
            hasAudioPermission,
            isAudioSessionReady,
            currentState != .listening && currentState != .processing,
            longPressBeganOnOrb
        ]
        let allMet = conditions.allSatisfy { $0 }
        if !allMet {
            Logger.recall.debug("Gate conditions not met: scrolling=\(isScrolling), cooldown=\(scrollCooldownActive), permission=\(hasAudioPermission), ready=\(isAudioSessionReady), state=\(currentState), onOrb=\(longPressBeganOnOrb)")
        }
        return allMet
    }
    
    // MARK: - Event Handlers
    
    private func handleLongPressBegan() {
        longPressBeganOnOrb = true
        
        switch currentState {
        case .idle:
            // Check gate conditions before transitioning to armed
            if canEnterListening() {
                transition(to: .armed)
            } else {
                Logger.recall.warning("Cannot enter listening: gate conditions not met")
                // Stay in idle, but mark that long press began
            }
        case .armed:
            // Already armed, check if we can transition to listening
            if canEnterListening() {
                transition(to: .listening)
            }
        case .listening, .processing:
            // Already in active state, ignore
            break
        case .responding:
            // Cancel response to allow new recording
            transition(to: .idle)
            handleLongPressBegan() // Retry
        case .error:
            // Reset from error
            transition(to: .idle)
            handleLongPressBegan() // Retry
        }
    }
    
    private func handleLongPressEnded() {
        longPressBeganOnOrb = false
        switch currentState {
        case .armed:
            transition(to: .idle)
        case .listening:
            transition(to: .processing)
        case .processing, .responding, .error, .idle:
            break
        }
    }

    private func handleUserTappedStart() {
        longPressBeganOnOrb = true
        switch currentState {
        case .idle:
            if canEnterListening() {
                transition(to: .armed)
                transition(to: .listening)
            }
        case .responding, .error:
            transition(to: .idle)
            handleUserTappedStart()
        default:
            break
        }
    }

    private func handleUserTappedStop() {
        longPressBeganOnOrb = false
        switch currentState {
        case .armed:
            transition(to: .idle)
        case .listening:
            transition(to: .processing)
        case .processing, .responding, .error:
            transition(to: .idle)
        case .idle:
            break
        }
    }
    
    private func handleWakeWordDetected() {
        // Similar to long press began, but triggered by wake word
        longPressBeganOnOrb = true
        
        switch currentState {
        case .idle:
            if canEnterListening() {
                transition(to: .armed)
                // Immediately transition to listening after armed
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay
                    if canEnterListening() {
                        transition(to: .listening)
                    }
                }
            }
        default:
            break
        }
    }
    
    private func handleSilenceTimeout() {
        if currentState == .listening {
            transition(to: .processing)
        }
    }
    
    private func handleCancel() {
        transition(to: .idle)
        longPressBeganOnOrb = false
    }
    
    private func handleResponseReceived() {
        if currentState == .processing {
            transition(to: .responding)
        }
    }
    
    private func handleError(_ error: Error) {
        lastError = error
        transition(to: .error)
        Logger.recall.error("State machine error: \(error.localizedDescription)")
    }
    
    // MARK: - State Transitions
    
    private func transition(to newState: RecallState) {
        let oldState = currentState
        currentState = newState
        
        Logger.recall.debug("State transition: \(oldState) -> \(newState)")
        
        // Provide haptic feedback for certain transitions
        switch (oldState, newState) {
        case (.idle, .armed):
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        case (.armed, .listening):
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
        case (.listening, .processing):
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        case (.processing, .responding):
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
        default:
            break
        }
    }
    
    // MARK: - Public Helpers
    
    func reset() {
        transition(to: .idle)
        longPressBeganOnOrb = false
        lastError = nil
        scrollCooldownTimer?.invalidate()
        scrollCooldownActive = false
    }
    
    func setLongPressBeganOnOrb(_ value: Bool) {
        longPressBeganOnOrb = value
    }
}

// MARK: - State and Event Definitions

/// State enum for Recall feature state machine
enum RecallState: Equatable {
    case idle
    case armed      // Long-press detected, checking gate conditions
    case listening  // Actively recording
    case processing // Processing recording (upload, transcription, AI)
    case responding // Assistant is speaking/responding
    case error
}

/// Event enum for Recall feature state machine
enum RecallStateMachineEvent {
    case longPressBegan
    case longPressEnded
    case userTappedStart   // Tap to start (Voice Mode - no long-press)
    case userTappedStop    // Tap to stop / deactivate listening
    case wakeWordDetected
    case scrollStarted
    case scrollEnded
    case silenceTimeout
    case cancel
    case responseReceived
    case error(Error)
}

