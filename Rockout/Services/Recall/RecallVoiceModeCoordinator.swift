import Foundation
import AVFoundation
import Combine

/// Wires AudioIOManager, VAD, STT, and RecallVoiceOrchestrator for Recall Voice Mode.
/// Handles barge-in (VAD during TTS → stop TTS, resume listening).
@MainActor
final class RecallVoiceModeCoordinator: ObservableObject {
    let orchestrator = RecallVoiceOrchestrator()
    
    private let audioManager = AudioIOManager.shared
    private let vad = VADService()
    private let stt = STTService()
    private let voiceResponse = VoiceResponseService.shared
    
    private var cancellables = Set<AnyCancellable>()
    private var isSessionActive = false
    
    init() {
        setupWiring()
    }
    
    private func setupWiring() {
        orchestrator.$currentState
            .sink { [weak self] state in
                self?.onOrchestratorStateChange(state)
            }
            .store(in: &cancellables)
        
        vad.onSpeechStart = { [weak self] in
            Task { @MainActor in
                self?.onVadSpeechStart()
            }
        }
        
        vad.onSpeechEnd = { [weak self] in
            Task { @MainActor in
                self?.onVadSpeechEnd()
            }
        }
        
        stt.onPartialResult = { [weak self] text in
            Task { @MainActor in
                self?.orchestrator.handleEvent(.sttPartial(text))
            }
        }
        
        stt.onFinalResult = { [weak self] text in
            Task { @MainActor in
                self?.orchestrator.handleEvent(.sttFinal(text))
            }
        }
    }
    
    private func onOrchestratorStateChange(_ state: RecallVoiceState) {
        switch state {
        case .listening, .capturingUtterance:
            if !isSessionActive {
                startAudioPipeline()
            }
        case .idle, .error, .interrupted:
            if isSessionActive && state != .interrupted {
                stopAudioPipeline()
            }
        case .speaking:
            break
        default:
            break
        }
    }
    
    private func onVadSpeechStart() {
        if orchestrator.currentState == .speaking {
            voiceResponse.stopSpeaking()
            orchestrator.handleEvent(.bargeInDetected)
            Logger.recall.info("RecallVoiceModeCoordinator: barge-in detected")
        } else if orchestrator.currentState == .listening {
            orchestrator.handleEvent(.vadSpeechStart)
        }
    }
    
    private func onVadSpeechEnd() {
        stt.endAudio()
        orchestrator.handleEvent(.vadSpeechEnd)
    }
    
    // MARK: - Audio Pipeline
    
    private func startAudioPipeline() {
        guard !isSessionActive else { return }
        
        do {
            try audioManager.configureForVoiceMode()
            audioManager.onAudioLevel = { [weak self] level in
                Task { @MainActor in
                    self?.vad.processLevel(level)
                }
            }
            audioManager.onAudioBufferForSTT = { [weak self] buffer in
                self?.stt.appendBuffer(buffer)
            }
            try audioManager.startCapture()
            
            vad.reset()
            try? stt.startRecognition()
            
            isSessionActive = true
            Logger.recall.info("RecallVoiceModeCoordinator: audio pipeline started")
        } catch {
            orchestrator.handleEvent(.errorOccurred(error))
            Logger.recall.error("RecallVoiceModeCoordinator: failed to start pipeline: \(error)")
        }
    }
    
    private func stopAudioPipeline() {
        guard isSessionActive else { return }
        
        audioManager.onAudioLevel = nil
        audioManager.onAudioBufferForSTT = nil
        audioManager.stopCapture()
        stt.stopRecognition()
        vad.reset()
        
        try? audioManager.deactivate()
        
        isSessionActive = false
        Logger.recall.info("RecallVoiceModeCoordinator: audio pipeline stopped")
    }
    
    // MARK: - Public
    
    func handleUserTappedStart() {
        orchestrator.handleEvent(.userTappedStart)
    }
    
    func handleUserTappedStop() {
        orchestrator.handleEvent(.userTappedStop)
        stopAudioPipeline()
    }
    
    func handleUserTappedMute() {
        orchestrator.handleEvent(.userTappedMute)
        stopAudioPipeline()
    }
    
    func handleUserTappedUnmute() {
        orchestrator.handleEvent(.userTappedUnmute)
        if orchestrator.currentState == .listening {
            startAudioPipeline()
        }
    }
    
    func endSession() {
        stopAudioPipeline()
        orchestrator.reset()
    }
    
    func requestSTTAuthorization() async -> Bool {
        let status = await STTService.requestAuthorization()
        return status == .authorized
    }
}
