import Foundation
import Combine
import UIKit

/// Voice Mode state machine — ChatGPT-style tap-to-start, VAD-based speech detection.
/// Replaces long-press with tap + automatic end-of-utterance.
@MainActor
final class RecallVoiceOrchestrator: ObservableObject {
    @Published var currentState: RecallVoiceState = .idle
    @Published var isMuted: Bool = false
    @Published var lastError: Error?
    @Published var audioLevel: CGFloat = 0.0
    @Published var liveTranscript: String = ""
    @Published var finalTranscript: String = ""

    private var cancellables = Set<AnyCancellable>()

    init() {}

    // MARK: - Events

    func handleEvent(_ event: RecallVoiceEvent) {
        Logger.recall.debug("RecallVoiceOrchestrator event: \(String(describing: event))")

        switch event {
        case .userTappedStart:
            handleUserTappedStart()
        case .userTappedStop:
            handleUserTappedStop()
        case .userTappedMute:
            handleUserTappedMute()
        case .userTappedUnmute:
            handleUserTappedUnmute()
        case .vadSpeechStart:
            handleVadSpeechStart()
        case .vadSpeechEnd:
            handleVadSpeechEnd()
        case .audioClassified(let type):
            handleAudioClassified(type)
        case .sttPartial(let text):
            handleSttPartial(text)
        case .sttFinal(let text):
            handleSttFinal(text)
        case .llmResponseReady:
            handleLlmResponseReady()
        case .ttsStarted:
            handleTtsStarted()
        case .ttsFinished:
            handleTtsFinished()
        case .bargeInDetected:
            handleBargeInDetected()
        case .errorOccurred(let error):
            handleError(error)
        case .recovered:
            handleRecovered()
        }
    }

    // MARK: - Event Handlers

    private func handleUserTappedStart() {
        switch currentState {
        case .idle:
            transition(to: .listening)
        case .listening, .capturingUtterance:
            break
        case .classifyingAudio, .transcribing, .thinking:
            break
        case .speaking:
            break
        case .interrupted, .error:
            transition(to: .listening)
        }
    }

    private func handleUserTappedStop() {
        switch currentState {
        case .idle:
            break
        case .listening, .capturingUtterance:
            transition(to: .idle)
        case .classifyingAudio, .transcribing, .thinking:
            transition(to: .idle)
        case .speaking:
            transition(to: .idle)
        case .interrupted, .error:
            transition(to: .idle)
        }
    }

    private func handleUserTappedMute() {
        isMuted = true
        switch currentState {
        case .listening, .capturingUtterance:
            transition(to: .idle)
        default:
            break
        }
    }

    private func handleUserTappedUnmute() {
        isMuted = false
        if case .idle = currentState {
            transition(to: .listening)
        }
    }

    private func handleVadSpeechStart() {
        if case .listening = currentState {
            transition(to: .capturingUtterance)
        }
    }

    private func handleVadSpeechEnd() {
        // Transition from listening or capturing so we always process when user stops speaking
        // (even if speech start was missed due to quiet beginning)
        switch currentState {
        case .listening, .capturingUtterance:
            transition(to: .classifyingAudio)
        default:
            break
        }
    }

    private func handleAudioClassified(_ type: AudioClassificationType) {
        if case .classifyingAudio = currentState {
            switch type {
            case .speech:
                transition(to: .transcribing)
            case .music, .hum:
                transition(to: .thinking)
            case .noise:
                transition(to: .idle)
            }
        }
    }

    private func handleSttPartial(_ text: String) {
        liveTranscript = text
    }

    private func handleSttFinal(_ text: String) {
        finalTranscript = text
        liveTranscript = text
        // Normal path: we're transcribing. Race: final can arrive while still classifying.
        switch currentState {
        case .transcribing, .classifyingAudio:
            transition(to: .thinking)
        default:
            break
        }
    }

    private func handleLlmResponseReady() {
        if case .thinking = currentState {
            transition(to: .speaking)
        }
    }

    private func handleTtsStarted() {
        if case .thinking = currentState {
            transition(to: .speaking)
        }
    }

    private func handleTtsFinished() {
        if case .speaking = currentState {
            // Stay in session: go back to listening for follow-up (user ends session by tapping orb).
            transition(to: .listening)
        }
    }

    private func handleBargeInDetected() {
        if case .speaking = currentState {
            transition(to: .interrupted)
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                transition(to: .listening)
            }
        }
    }

    private func handleError(_ error: Error) {
        lastError = error
        transition(to: .error)
        Logger.recall.error("RecallVoiceOrchestrator error: \(error.localizedDescription)")
    }

    private func handleRecovered() {
        lastError = nil
        transition(to: .idle)
    }

    // MARK: - Transitions

    private func transition(to newState: RecallVoiceState) {
        let oldState = currentState
        currentState = newState

        Logger.recall.debug("RecallVoiceOrchestrator: \(oldState) -> \(newState)")

        switch (oldState, newState) {
        case (.idle, .listening):
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        case (.listening, .capturingUtterance), (.capturingUtterance, .classifyingAudio):
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        case (.thinking, .speaking):
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
        default:
            break
        }
    }

    // MARK: - Public

    func reset() {
        currentState = .idle
        isMuted = false
        lastError = nil
        audioLevel = 0
        liveTranscript = ""
        finalTranscript = ""
    }

    func updateAudioLevel(_ level: CGFloat) {
        audioLevel = level
    }
}

// MARK: - State & Events

enum RecallVoiceState: Equatable {
    case idle
    case listening
    case capturingUtterance
    case classifyingAudio
    case transcribing
    case thinking
    case speaking
    case interrupted
    case error
}

enum RecallVoiceEvent {
    case userTappedStart
    case userTappedStop
    case userTappedMute
    case userTappedUnmute
    case vadSpeechStart
    case vadSpeechEnd
    case audioClassified(AudioClassificationType)
    case sttPartial(String)
    case sttFinal(String)
    case llmResponseReady
    case ttsStarted
    case ttsFinished
    case bargeInDetected
    case errorOccurred(Error)
    case recovered
}

enum AudioClassificationType {
    case speech
    case music
    case hum
    case noise
}
