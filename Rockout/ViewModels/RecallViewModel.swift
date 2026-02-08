import Foundation
import SwiftUI
import Combine
import UIKit
import AVFoundation

/// Conversation mode for Recall feature
enum ConversationMode {
    case idle
    case speaking
    case waitingForRefinement
}

@MainActor
final class RecallViewModel: ObservableObject {
    @Published var currentThreadId: UUID?
    @Published var messages: [RecallMessage] = []
    @Published var composerText: String = ""
    @Published var orbState: RecallOrbState = .idle
    @Published var selectedImage: UIImage?
    @Published var isResolving: Bool = false
    @Published var errorMessage: String?
    
    // Additional properties for UI integration
    @Published var isProcessing: Bool = false
    @Published var conversationMode: ConversationMode = .idle
    @Published var isSpeaking: Bool = false
    @Published var pendingTranscript: (text: String, messageType: RecallMessageType, id: UUID)?
    @Published var showGreenRoomPrompt: Bool = false
    @Published var greenRoomPromptText: String = ""
    @Published var showRepromptSheet: Bool = false
    @Published var repromptMessageId: UUID?
    @Published var repromptOriginalQuery: String?
    @Published var lastUserQuery: String?
    var rejectionCount: Int = 0
    
    // Transcript management
    @Published var liveTranscript: String = ""
    @Published var rawTranscript: String?
    @Published var editedTranscript: String?
    @Published var showTranscriptComposer: Bool = false
    @Published var draftTranscript: String?
    
    // Session-based flag to track if welcome has been shown
    // Resets when app restarts (not when switching threads)
    private var hasShownWelcomeThisSession: Bool = false
    
    var canTerminateSession: Bool {
        !messages.isEmpty
    }
    
    private let service = RecallService.shared
    private let voiceRecorder = VoiceRecorder()
    let stateMachine = RecallStateMachine() // State machine for gate conditions
    private let audioSessionManager = AudioSessionManager.shared
    /// Voice Mode: tap-to-start, VAD-based end-of-utterance (ChatGPT-style).
    let voiceOrchestrator = RecallVoiceOrchestrator()
    private let vadService = VADService()
    private let audioIOManager = AudioIOManager.shared
    private let sttService = STTService()
    private let toolRouter = RecallToolRouter.shared

    /// True when voice session is active (listening or processing); drives orb from orchestrator.
    @Published var isVoiceModeActive: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var messageLoadTask: Task<Void, Never>?
    /// STT-based fallback: when no new partial for this duration, treat as "done speaking" and auto-send (even if VAD didn't fire).
    private var utteranceSilenceTimer: Timer?
    private let utteranceSilenceInterval: TimeInterval = 1.0
    /// Throttle VAD to this interval so we don't flood MainActor (efficient ~30 Hz sampling).
    private let vadSampleInterval: TimeInterval = 0.032
    private var lastVadProcessTime: Date = .distantPast

    /// UserDefaults key for Recall settings (must match RecallSettingsView @AppStorage).
    private static let autoSpeakResponsesKey = "recall.autoSpeakResponses"

    private var autoSpeakResponses: Bool {
        UserDefaults.standard.object(forKey: Self.autoSpeakResponsesKey) as? Bool ?? true
    }

    init() {
        // Voice Mode: drive orb state from orchestrator when voice session is active
        voiceOrchestrator.$currentState
            .sink { [weak self] state in
                guard let self = self else { return }
                self.syncOrbStateFromVoiceOrchestrator(state)
            }
            .store(in: &cancellables)
        audioIOManager.$audioLevel
            .sink { [weak self] level in
                guard let self = self else { return }
                if self.isVoiceModeActive, case .listening = self.orbState {
                    self.orbState = .listening(level: level)
                }
            }
            .store(in: &cancellables)

        // Observe state machine state and update orbState (when not in voice mode)
        stateMachine.$currentState
            .sink { [weak self] state in
                guard let self = self else { return }
                guard !self.isVoiceModeActive else { return }
                // Convert RecallState to RecallOrbState
                switch state {
                case .idle:
                    if case .idle = self.orbState { return }
                    self.orbState = .idle
                case .armed:
                    self.orbState = .armed
                case .listening:
                    if case .listening(let level) = self.orbState {
                        self.orbState = .listening(level: level)
                    } else {
                        self.orbState = .listening(level: 0.5)
                    }
                case .processing:
                    self.orbState = .thinking
                case .responding:
                    self.orbState = .responding
                case .error:
                    self.orbState = .error
                }
            }
            .store(in: &cancellables)
        
        // Observe state machine scroll state
        stateMachine.$isScrolling
            .sink { [weak self] isScrolling in
                // Can be used for UI updates if needed
            }
            .store(in: &cancellables)
        
        // Observe voice recorder state
        voiceRecorder.$isRecording
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if isRecording {
                    // Recording started - transition to listening state if we're in armed state
                    if self.stateMachine.currentState == .armed {
                        // Check if we can enter listening (gate conditions should still be met)
                        if self.stateMachine.canEnterListening() {
                            // Transition to listening
                            self.stateMachine.handleEvent(.longPressBegan) // This will transition armed -> listening
                        }
                    }
                } else {
                    // Recording stopped - don't trigger state machine here
                    // The state machine is already handled by orbLongPressEnded()
                    // This observer should not interfere with manual stop
                }
            }
            .store(in: &cancellables)
        
        audioSessionManager.$isInterrupted
            .removeDuplicates()
            .sink { [weak self] interrupted in
                guard let self = self else { return }
                if !interrupted, self.voiceOrchestrator.currentState == .error {
                    Logger.recall.info("Audio session recovered from interruption")
                    self.voiceOrchestrator.handleEvent(.recovered)
                }
            }
            .store(in: &cancellables)

        voiceRecorder.$meterLevel
            .sink { [weak self] level in
                guard let self = self else { return }
                if case .listening = self.orbState {
                    self.orbState = .listening(level: level)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Voice Mode (Orchestrator + VAD)

    private func syncOrbStateFromVoiceOrchestrator(_ state: RecallVoiceState) {
        switch state {
        case .idle, .interrupted:
            isVoiceModeActive = false
            orbState = .idle
        case .listening, .capturingUtterance:
            isVoiceModeActive = true
            orbState = .listening(level: CGFloat(audioIOManager.audioLevel))
        case .classifyingAudio, .transcribing, .thinking:
            isVoiceModeActive = true
            orbState = .thinking
        case .speaking:
            isVoiceModeActive = true
            orbState = .responding
        case .error:
            isVoiceModeActive = true
            orbState = .error
        }
    }

    private func startVoiceModeCapture() {
        vadService.reset()
        vadService.bargeInMode = false
        vadService.onSpeechStart = { [weak self] in
            Task { @MainActor in
                self?.voiceOrchestrator.handleEvent(.vadSpeechStart)
            }
        }
        vadService.onSpeechEnd = { [weak self] in
            Task { @MainActor in
                self?.handleVadSpeechEnd()
            }
        }
        vadService.onBargeIn = { [weak self] in
            Task { @MainActor in
                VoiceResponseService.shared.stopSpeaking()
                self?.voiceOrchestrator.handleEvent(.bargeInDetected)
            }
        }
        lastVadProcessTime = .distantPast
        audioIOManager.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.processLevelForVadIfNeeded(level)
            }
        }
        Task {
            do {
                let hasPermission = await audioSessionManager.requestMicrophonePermission()
                guard hasPermission else {
                    let err = NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"])
                    Logger.recall.error("Voice Mode: mic permission denied")
                    voiceOrchestrator.handleEvent(.errorOccurred(err))
                    errorMessage = "Microphone access is required. Enable it in Settings."
                    return
                }
                try audioSessionManager.configureForPlayAndRecord()
                try audioIOManager.startCapture()
                let sttAuthorized = await STTService.requestAuthorization()
                if sttAuthorized == .authorized {
                    sttService.onPartialResult = { [weak self] text in
                        Task { @MainActor in
                            self?.voiceOrchestrator.handleEvent(.sttPartial(text))
                            self?.liveTranscript = text
                            self?.scheduleUtteranceSilenceTimer()
                        }
                    }
                    sttService.onFinalResult = { [weak self] text in
                        Task { @MainActor in
                            self?.voiceOrchestrator.handleEvent(.sttFinal(text))
                            self?.handleVoiceModeSttFinal(transcript: text)
                        }
                    }
                    audioIOManager.onAudioBufferForSTT = { [weak self] buffer in
                        self?.sttService.appendBuffer(buffer)
                    }
                    try sttService.startRecognition()
                    Logger.recall.info("Voice Mode: capture started with STT")
                } else {
                    startVoiceModeCaptureFallback()
                }
            } catch {
                Logger.recall.warning("Voice Mode STT failed, using fallback: \(error.localizedDescription)")
                startVoiceModeCaptureFallback()
            }
        }
    }

    /// Fallback when STT unavailable: VoiceRecorder + upload + Whisper. Uses 2.5s silence auto-stop.
    private func startVoiceModeCaptureFallback() {
        audioIOManager.stopCapture()
        audioIOManager.onAudioLevel = nil
        audioIOManager.onAudioBufferForSTT = nil
        var hasHandled = false
        let cancellable = voiceRecorder.$isRecording
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self = self, !hasHandled else { return }
                hasHandled = true
                Task { @MainActor in
                    self.voiceOrchestrator.handleEvent(.vadSpeechEnd)
                    let audioType = self.classifyFallbackAudio()
                    self.voiceOrchestrator.handleEvent(.audioClassified(audioType))
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if audioType == .speech {
                        await self.handleVoiceRecording()
                    } else if audioType == .music || audioType == .hum {
                        await self.handleVoiceRecordingAsMusicHum(audioType: audioType)
                    } else {
                        self.voiceOrchestrator.handleEvent(.errorOccurred(RecallToolRouterError.noiseIgnored))
                    }
                }
            }
        cancellables.insert(AnyCancellable { cancellable.cancel() })
        Task {
            do {
                try await voiceRecorder.startRecording()
                Logger.recall.info("Voice Mode: capture started (fallback: upload+Whisper)")
            } catch {
                Logger.recall.error("Voice Mode fallback start failed: \(error.localizedDescription)")
                voiceOrchestrator.handleEvent(.errorOccurred(error))
            }
        }
    }

    private func classifyFallbackAudio() -> AudioClassificationType {
        guard let url = voiceRecorder.recordingURL else { return .speech }
        return AudioTypeClassifier.shared.classify(file: url) ?? .speech
    }

    private func handleVoiceRecordingAsMusicHum(audioType: AudioClassificationType) async {
        guard let threadId = currentThreadId,
              let recordingURL = voiceRecorder.recordingURL else {
            voiceOrchestrator.handleEvent(.errorOccurred(NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No recording"])))
            return
        }
        isProcessing = true
        orbState = .thinking
        do {
            let audioData = try Data(contentsOf: recordingURL)
            let fileName = "voice_\(Int(Date().timeIntervalSince1970)).m4a"
            let mediaPath = try await service.uploadMedia(
                data: audioData,
                threadId: threadId,
                fileName: fileName,
                contentType: "audio/m4a"
            )
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .voice,
                mediaPath: mediaPath
            )
            await loadMessages()
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Identifying song..."
            )
            await loadMessages()
            let response = try await toolRouter.resolve(
                threadId: threadId,
                messageId: messageId,
                audioType: audioType,
                text: nil,
                mediaPath: mediaPath
            )
            voiceOrchestrator.handleEvent(.llmResponseReady)
            isProcessing = false
            let textToSpeak = response.assistantMessage.map({ "I found \($0.songTitle) by \($0.songArtist). \($0.reason)" })
                ?? response.candidates?.first.map({ "I found \($0.title) by \($0.artist). \($0.reason)" })
            if let text = textToSpeak, autoSpeakResponses {
                startBargeInCapture()
                VoiceResponseService.shared.speak(text, completion: { [weak self] in
                    Task { @MainActor in
                        self?.stopBargeInCapture()
                        self?.voiceOrchestrator.handleEvent(.ttsFinished)
                        self?.isProcessing = false
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        self?.startVoiceModeCapture()
                    }
                }, usePlayAndRecord: true)
                voiceOrchestrator.handleEvent(.ttsStarted)
            } else {
                voiceOrchestrator.handleEvent(.ttsFinished)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    startVoiceModeCapture()
                }
            }
            Task { await handleVoiceResponse(response, messageId: messageId, threadId: threadId) }
            try? FileManager.default.removeItem(at: recordingURL)
            voiceRecorder.recordingURL = nil
        } catch {
            voiceOrchestrator.handleEvent(.errorOccurred(error))
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    private func stopVoiceModeCapture(clearSttCallbacks: Bool = true) {
        utteranceSilenceTimer?.invalidate()
        utteranceSilenceTimer = nil
        audioIOManager.onAudioLevel = nil
        audioIOManager.onAudioBufferForSTT = nil
        audioIOManager.onAudioBuffer = nil
        vadService.onSpeechStart = nil
        vadService.onSpeechEnd = nil
        vadService.onBargeIn = nil
        vadService.reset()
        if clearSttCallbacks {
            sttService.onPartialResult = nil
            sttService.onFinalResult = nil
            sttService.stopRecognition()
        }
        audioIOManager.stopCapture()
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
        }
        Logger.recall.info("Voice Mode: capture stopped")
    }

    /// Throttle VAD to ~30 Hz so we don't flood MainActor; keeps speech detection responsive and efficient.
    private func processLevelForVadIfNeeded(_ level: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastVadProcessTime) >= vadSampleInterval else { return }
        lastVadProcessTime = now
        vadService.processLevel(level)
    }

    /// When we have partial STT and no new partial for a short time, treat as "done speaking" and send (fallback if VAD didn't fire).
    private func scheduleUtteranceSilenceTimer() {
        utteranceSilenceTimer?.invalidate()
        utteranceSilenceTimer = nil
        guard !liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        utteranceSilenceTimer = Timer.scheduledTimer(withTimeInterval: utteranceSilenceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.utteranceSilenceTimer = nil
                guard let self = self else { return }
                let state = self.voiceOrchestrator.currentState
                guard state == .listening || state == .capturingUtterance else { return }
                guard !self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Logger.recall.info("Voice Mode: STT utterance silence (\(self.utteranceSilenceInterval)s) — auto-sending")
                self.handleVadSpeechEnd()
            }
        }
        utteranceSilenceTimer?.tolerance = 0.1
        if let t = utteranceSilenceTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func handleVadSpeechEnd() {
        sttService.endAudio()
        stopVoiceModeCapture(clearSttCallbacks: false)
        voiceOrchestrator.handleEvent(.vadSpeechEnd)
        voiceOrchestrator.handleEvent(.audioClassified(.speech))
    }

    private func handleVoiceModeSttFinal(transcript: String) {
        stopVoiceModeCapture(clearSttCallbacks: true)
        liveTranscript = ""
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            voiceOrchestrator.handleEvent(.errorOccurred(RecallToolRouterError.emptyTranscript))
            return
        }
        Task {
            await resolveVoiceModeWithTranscript(text)
        }
    }

    private func resolveVoiceModeWithTranscript(_ transcript: String) async {
        guard let threadId = currentThreadId else {
            voiceOrchestrator.handleEvent(.errorOccurred(NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No thread"])))
            return
        }
        isProcessing = true
        do {
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .voice,
                text: transcript
            )
            await loadMessages()
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching..."
            )
            await loadMessages()
            let response = try await toolRouter.resolve(
                threadId: threadId,
                messageId: messageId,
                audioType: .speech,
                text: transcript,
                mediaPath: nil
            )
            voiceOrchestrator.handleEvent(.llmResponseReady)
            isProcessing = false
            let textToSpeak: String? = {
                if let answerText = response.answer?.text { return answerText }
                if let msg = response.assistantMessage {
                    return "I found \(msg.songTitle) by \(msg.songArtist). \(msg.reason)"
                }
                if let first = response.candidates?.first {
                    return "I found \(first.title) by \(first.artist). \(first.reason)"
                }
                return nil
            }()
            if let text = textToSpeak, autoSpeakResponses {
                startBargeInCapture()
                VoiceResponseService.shared.speak(text, completion: { [weak self] in
                    Task { @MainActor in
                        self?.stopBargeInCapture()
                        self?.voiceOrchestrator.handleEvent(.ttsFinished)
                        self?.isProcessing = false
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        self?.startVoiceModeCapture()
                    }
                }, usePlayAndRecord: true)
                voiceOrchestrator.handleEvent(.ttsStarted)
            } else {
                voiceOrchestrator.handleEvent(.ttsFinished)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    startVoiceModeCapture()
                }
            }
            Task { await handleVoiceResponse(response, messageId: messageId, threadId: threadId) }
        } catch {
            voiceOrchestrator.handleEvent(.errorOccurred(error))
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    private func startBargeInCapture() {
        vadService.reset()
        vadService.bargeInMode = true
        vadService.onBargeIn = { [weak self] in
            Task { @MainActor in
                VoiceResponseService.shared.stopSpeaking()
                self?.stopBargeInCapture()
                self?.voiceOrchestrator.handleEvent(.bargeInDetected)
                self?.startVoiceModeCapture()
            }
        }
        lastVadProcessTime = .distantPast
        audioIOManager.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.processLevelForVadIfNeeded(level)
            }
        }
        do {
            try audioSessionManager.configureForPlayAndRecord()
            try audioIOManager.startCapture()
            Logger.recall.info("Voice Mode: barge-in capture started")
        } catch {
            Logger.recall.error("Voice Mode barge-in start failed: \(error.localizedDescription)")
        }
    }

    private func stopBargeInCapture() {
        audioIOManager.onAudioLevel = nil
        vadService.onBargeIn = nil
        vadService.reset()
        audioIOManager.stopCapture()
        Logger.recall.info("Voice Mode: barge-in capture stopped")
    }

    /// Voice Mode: Mute = pause listening (stay in session).
    func voiceModeMute() {
        voiceOrchestrator.handleEvent(.userTappedMute)
        stopVoiceModeCapture()
    }

    /// Voice Mode: Unmute = resume listening.
    func voiceModeUnmute() {
        voiceOrchestrator.handleEvent(.userTappedUnmute)
        if voiceOrchestrator.currentState == .idle {
            voiceOrchestrator.handleEvent(.userTappedStart)
        }
        startVoiceModeCapture()
    }

    /// Voice Mode: Exit = end session, return to idle.
    func voiceModeExit() {
        voiceOrchestrator.handleEvent(.userTappedStop)
        stopVoiceModeCapture()
        voiceOrchestrator.reset()
        isVoiceModeActive = false
        orbState = .idle
        stateMachine.reset()
    }

    // MARK: - Thread Management
    
    func startNewThreadIfNeeded() async {
        do {
            let threadId = try await service.createThreadIfNeeded()
            currentThreadId = threadId
            await loadMessages()
        } catch {
            errorMessage = "Failed to create thread: \(error.localizedDescription)"
            print("❌ Failed to create thread: \(error)")
        }
    }
    
    @Published var isLoadingOlderMessages: Bool = false
    @Published var hasMoreMessages: Bool = false
    private var messageCursor: Date?
    
    func loadMessages(forceRefresh: Bool = false) {
        // Cancel previous load if still in flight
        messageLoadTask?.cancel()
        
        // Debounce rapid calls (300ms) unless force refresh
        messageLoadTask = Task { @MainActor in
            if !forceRefresh {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            }
            
            guard !Task.isCancelled else { return }
            
            await loadMessagesInternal()
        }
    }
    
    private func loadMessagesInternal() async {
        guard let threadId = currentThreadId else { return }
        
        do {
            let result = try await service.fetchMessages(threadId: threadId, cursor: nil, limit: 50)
            messages = result.messages
            messageCursor = result.messages.last?.createdAt
            hasMoreMessages = result.hasMore
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
            print("❌ Failed to load messages: \(error)")
        }
    }
    
    func loadOlderMessages() async {
        guard let threadId = currentThreadId,
              let cursor = messageCursor,
              !isLoadingOlderMessages,
              hasMoreMessages else {
            return
        }
        
        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        
        do {
            let result = try await service.fetchMessages(threadId: threadId, cursor: cursor, limit: 50)
            let olderMessages = result.messages
            messages = olderMessages + messages // Prepend older messages
            messageCursor = olderMessages.last?.createdAt
            hasMoreMessages = result.hasMore
        } catch {
            errorMessage = "Failed to load older messages: \(error.localizedDescription)"
            Logger.recall.error("Failed to load older messages: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Transcript
    
    func sendTranscript(_ finalText: String) async {
        if currentThreadId == nil {
            do {
                let threadId = try await service.createNewThread()
                currentThreadId = threadId
                await loadMessages()
            } catch {
                errorMessage = "Failed to create thread: \(error.localizedDescription)"
                return
            }
        }
        guard let threadId = currentThreadId,
              !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let text = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clear transcript state
        rawTranscript = nil
        editedTranscript = nil
        showTranscriptComposer = false
        draftTranscript = nil
        
        do {
            // Insert user message with both raw and edited transcripts
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .voice,
                text: text,
                rawTranscript: rawTranscript,
                editedTranscript: editedTranscript ?? text
            )
            
            // Reload messages
            await loadMessages()
            
            // Insert status message
            let statusMessageId = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching..."
            )
            
            await loadMessages()
            
            // Resolve - use edited transcript if available, else raw, else text
            let queryText = editedTranscript ?? rawTranscript ?? text
            
            // Resolve
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .voice,
                text: queryText
            )
            
            // Handle response similar to handleVoiceRecording
            await handleVoiceResponse(response, messageId: messageId, threadId: threadId)
        } catch {
            errorMessage = "Failed to send transcript: \(error.localizedDescription)"
            Logger.recall.error("Failed to send transcript: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Text
    
    func sendText() async {
        if currentThreadId == nil {
            do {
                let threadId = try await service.createNewThread()
                currentThreadId = threadId
                await loadMessages()
            } catch {
                errorMessage = "Failed to create thread: \(error.localizedDescription)"
                return
            }
        }
        guard let threadId = currentThreadId,
              !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        composerText = ""
        
        do {
            // Insert user message
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .text,
                text: text
            )
            
            // Reload messages
            await loadMessages()
            
            // Insert status message
            let statusMessageId = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching..."
            )
            
            await loadMessages()
            orbState = .thinking
            
            // Resolve
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .text,
                text: text
            )
            
            // Update status message with result
            if let assistantMessage = response.assistantMessage {
                let candidateJson: [String: AnyCodable] = [
                    "title": AnyCodable(assistantMessage.songTitle),
                    "artist": AnyCodable(assistantMessage.songArtist),
                    "confidence": AnyCodable(assistantMessage.confidence),
                    "reason": AnyCodable(assistantMessage.reason),
                    "lyric_snippet": AnyCodable(assistantMessage.lyricSnippet ?? "")
                ]
                
                // Update the status message to candidate
                // Note: In a real implementation, we'd update the existing message
                // For now, we'll insert a new candidate message
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .candidate,
                    text: "\(assistantMessage.songTitle) by \(assistantMessage.songArtist)",
                    candidateJson: candidateJson,
                    sourcesJson: assistantMessage.sources,
                    confidence: assistantMessage.confidence,
                    songUrl: assistantMessage.songUrl,
                    songTitle: assistantMessage.songTitle,
                    songArtist: assistantMessage.songArtist
                )
            }
            
            await loadMessages()
            isProcessing = false
            
            // Update orb state based on confidence
            if let confidence = response.assistantMessage?.confidence {
                orbState = .done(confidence: confidence)
                stateMachine.handleEvent(.responseReceived)
                
                // Reset to idle after 2 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        stateMachine.reset()
                    }
                }
            } else {
                orbState = .error
                stateMachine.handleEvent(.error(NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response received"])))
            }
            
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            orbState = .error
            isProcessing = false
            stateMachine.handleEvent(.error(error))
            print("❌ Failed to send text: \(error)")
        }
    }
    
    // MARK: - Pick Image
    
    func pickImage(_ image: UIImage) async {
        selectedImage = image
        await sendImage()
    }
    
    private func sendImage() async {
        guard let threadId = currentThreadId,
              let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.7) else {
            return
        }
        
        selectedImage = nil
        
        do {
            // Compress and resize if needed
            let finalImage: UIImage
            if image.size.width > 1024 || image.size.height > 1024 {
                let maxDimension: CGFloat = 1024
                let ratio = min(maxDimension / image.size.width, maxDimension / image.size.height)
                let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                finalImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
            } else {
                finalImage = image
            }
            
            guard let finalData = finalImage.jpegData(compressionQuality: 0.7) else {
                throw NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
            }
            
            // Upload
            let fileName = "image_\(Int(Date().timeIntervalSince1970)).jpg"
            let mediaPath = try await service.uploadMedia(
                data: finalData,
                threadId: threadId,
                fileName: fileName,
                contentType: "image/jpeg"
            )
            
            // Insert user message
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .image,
                mediaPath: mediaPath
            )
            
            await loadMessages()
            
            // Insert status message
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching..."
            )
            
            await loadMessages()
            orbState = .thinking
            
            // Resolve
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .image,
                mediaPath: mediaPath
            )
            
            // Update with candidate (same as text flow)
            if let assistantMessage = response.assistantMessage {
                let candidateJson: [String: AnyCodable] = [
                    "title": AnyCodable(assistantMessage.songTitle),
                    "artist": AnyCodable(assistantMessage.songArtist),
                    "confidence": AnyCodable(assistantMessage.confidence),
                    "reason": AnyCodable(assistantMessage.reason),
                    "lyric_snippet": AnyCodable(assistantMessage.lyricSnippet ?? "")
                ]
                
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .candidate,
                    text: "\(assistantMessage.songTitle) by \(assistantMessage.songArtist)",
                    candidateJson: candidateJson,
                    sourcesJson: assistantMessage.sources,
                    confidence: assistantMessage.confidence,
                    songUrl: assistantMessage.songUrl,
                    songTitle: assistantMessage.songTitle,
                    songArtist: assistantMessage.songArtist
                )
            }
            
            await loadMessages()
            isProcessing = false
            
            if let confidence = response.assistantMessage?.confidence {
                orbState = .done(confidence: confidence)
                stateMachine.handleEvent(.responseReceived)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        stateMachine.reset()
                    }
                }
            } else {
                orbState = .error
                stateMachine.handleEvent(.error(NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response received"])))
            }
            
        } catch {
            errorMessage = "Failed to send image: \(error.localizedDescription)"
            orbState = .error
            isProcessing = false
            stateMachine.handleEvent(.error(error))
            print("❌ Failed to send image: \(error)")
        }
    }
    
    // MARK: - Orb Tapped / Long Press
    
    func orbLongPressed() async {
        let requestId = UUID().uuidString.prefix(8)
        let startTime = Date()
        
        print("🔍 [RECALL-VIEWMODEL] [\(requestId)] orbLongPressed() called")
        print("📊 [RECALL-VIEWMODEL] [\(requestId)] Current state: \(stateMachine.currentState), isRecording: \(voiceRecorder.isRecording)")
        
        // Notify state machine
        stateMachine.handleEvent(.longPressBegan)
        
        // Check if state machine allows entering listening state
        guard stateMachine.currentState == .armed || stateMachine.currentState == .listening else {
            // Gate conditions not met, cannot start recording
            print("⚠️ [RECALL-VIEWMODEL] [\(requestId)] Cannot start recording: gate conditions not met (state: \(stateMachine.currentState))")
            return
        }
        
        if voiceRecorder.isRecording {
            // Already recording, ignore
            print("⚠️ [RECALL-VIEWMODEL] [\(requestId)] Already recording, ignoring duplicate start")
            return
        }
        
        // Start recording
        do {
            print("🎤 [RECALL-VIEWMODEL] [\(requestId)] Starting voice recording...")
            let recordingStartTime = Date()
            try await voiceRecorder.startRecording()
            let recordingStartDuration = Date().timeIntervalSince(recordingStartTime)
            print("✅ [RECALL-VIEWMODEL] [\(requestId)] Recording started successfully in \(String(format: "%.3f", recordingStartDuration))s")
            print("📊 [RECALL-VIEWMODEL] [\(requestId)] Recording state: isRecording=\(voiceRecorder.isRecording), URL=\(voiceRecorder.recordingURL?.lastPathComponent ?? "nil")")
            // The state transition to listening will be handled by the voiceRecorder observation
            // which triggers when isRecording becomes true
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            stateMachine.handleEvent(.error(error))
            print("❌ [RECALL-VIEWMODEL] [\(requestId)] Failed to start recording after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
            if let nsError = error as? NSError {
                print("   Error code: \(nsError.code), domain: \(nsError.domain)")
            }
        }
    }
    
    func orbLongPressEnded() async {
        let requestId = UUID().uuidString.prefix(8)
        let startTime = Date()
        
        print("🛑 [RECALL-VIEWMODEL] [\(requestId)] orbLongPressEnded() called")
        print("📊 [RECALL-VIEWMODEL] [\(requestId)] Current state: isRecording=\(voiceRecorder.isRecording), stateMachine=\(stateMachine.currentState)")
        
        // Stop recording immediately when contact is lost
        guard voiceRecorder.isRecording else {
            // Not recording, just update state machine and reset
            print("⚠️ [RECALL-VIEWMODEL] [\(requestId)] Not recording, just updating state machine")
            stateMachine.handleEvent(.longPressEnded)
            stateMachine.setLongPressBeganOnOrb(false)
            // Reset to idle to allow new sessions
            if stateMachine.currentState == .processing {
                stateMachine.reset()
            }
            return
        }
        
        // Stop recording FIRST, before updating state machine
        print("🛑 [RECALL-VIEWMODEL] [\(requestId)] Stopping recording...")
        let stopStartTime = Date()
        voiceRecorder.stopRecording()
        let stopDuration = Date().timeIntervalSince(stopStartTime)
        print("⏱️ [RECALL-VIEWMODEL] [\(requestId)] stopRecording() took \(String(format: "%.3f", stopDuration))s")
        
        // Wait a brief moment to ensure recording has fully stopped
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Verify recording has stopped - force stop if still active
        if voiceRecorder.isRecording {
            print("⚠️ [RECALL-VIEWMODEL] [\(requestId)] Recording still active after stop, forcing stop again...")
            voiceRecorder.stopRecording()
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        print("✅ [RECALL-VIEWMODEL] [\(requestId)] Recording stopped: isRecording=\(voiceRecorder.isRecording)")
        if let recordingURL = voiceRecorder.recordingURL {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: recordingURL.path)[.size] as? Int64) ?? 0
            print("📁 [RECALL-VIEWMODEL] [\(requestId)] Recording file: \(recordingURL.lastPathComponent), size: \(fileSize) bytes")
        }
        
        // Update state machine after stopping
        stateMachine.handleEvent(.longPressEnded)
        stateMachine.setLongPressBeganOnOrb(false)
        
        let totalDuration = Date().timeIntervalSince(startTime)
        print("⏱️ [RECALL-VIEWMODEL] [\(requestId)] orbLongPressEnded() completed in \(String(format: "%.3f", totalDuration))s, proceeding to handleVoiceRecording()")
        
        // Process the recording
        await handleVoiceRecording()
    }
    
    func orbTapped() async {
        if voiceRecorder.isRecording {
            stateMachine.handleEvent(.longPressEnded)
            voiceRecorder.stopRecording()
            await handleVoiceRecording()
        } else {
            stateMachine.handleEvent(.longPressBegan)
            guard stateMachine.currentState == .armed || stateMachine.currentState == .listening else { return }
            do {
                try await voiceRecorder.startRecording()
            } catch {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                stateMachine.handleEvent(.error(error))
            }
        }
    }

    /// Voice Mode: tap to start, tap again to stop. VAD drives end-of-utterance. No long-press.
    func orbTappedForVoiceMode() async {
        let state = voiceOrchestrator.currentState
        switch state {
        case .idle, .error, .interrupted:
            // After ending a session, currentThreadId is nil — create a new thread so requests can be processed
            if currentThreadId == nil {
                do {
                    let threadId = try await service.createNewThread()
                    currentThreadId = threadId
                    await loadMessages()
                    Logger.recall.info("Created new thread for voice session: \(threadId.uuidString)")
                } catch {
                    errorMessage = "Failed to create thread: \(error.localizedDescription)"
                    Logger.recall.error("Failed to create thread for voice mode: \(error.localizedDescription)")
                    return
                }
            }
            voiceOrchestrator.handleEvent(.userTappedStart)
            if voiceOrchestrator.currentState == .listening {
                startVoiceModeCapture()
            }
        case .listening, .capturingUtterance:
            voiceOrchestrator.handleEvent(.userTappedStop)
            stopVoiceModeCapture()
        case .classifyingAudio, .transcribing, .thinking, .speaking:
            voiceOrchestrator.handleEvent(.userTappedStop)
            stopVoiceModeCapture()
        }
    }
    
    private func handleVoiceRecording() async {
        let requestId = UUID().uuidString.prefix(8)
        let startTime = Date()
        
        print("🔍 [RECALL-VIEWMODEL] [\(requestId)] handleVoiceRecording() started")
        
        // Ensure recording has actually stopped
        if voiceRecorder.isRecording {
            print("⚠️ [RECALL-VIEWMODEL] [\(requestId)] Recording still active, forcing stop...")
            voiceRecorder.stopRecording()
            // Wait a moment for it to fully stop
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
        
        guard let threadId = currentThreadId,
              let recordingURL = voiceRecorder.recordingURL else {
            print("❌ [RECALL-VIEWMODEL] [\(requestId)] Missing threadId or recordingURL")
            print("   threadId: \(currentThreadId?.uuidString ?? "nil")")
            print("   recordingURL: \(voiceRecorder.recordingURL?.lastPathComponent ?? "nil")")
            orbState = .error
            stateMachine.handleEvent(.error(NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No recording URL"])))
            voiceOrchestrator.reset()
            isVoiceModeActive = false
            return
        }
        
        print("📊 [RECALL-VIEWMODEL] [\(requestId)] Processing recording:")
        print("   threadId: \(threadId.uuidString)")
        print("   recordingURL: \(recordingURL.lastPathComponent)")
        
        orbState = .thinking
        isProcessing = true
        // Reset long press flag when we actually stop recording
        stateMachine.setLongPressBeganOnOrb(false)
        // State machine should already be in processing state from orbLongPressEnded
        
        do {
            // Read audio data
            let readStartTime = Date()
            let audioData = try Data(contentsOf: recordingURL)
            let readDuration = Date().timeIntervalSince(readStartTime)
            let audioSize = audioData.count
            print("📁 [RECALL-VIEWMODEL] [\(requestId)] Audio file read: \(audioSize) bytes in \(String(format: "%.3f", readDuration))s")
            
            // Upload
            let uploadStartTime = Date()
            let fileName = "voice_\(Int(Date().timeIntervalSince1970)).m4a"
            print("📤 [RECALL-VIEWMODEL] [\(requestId)] Uploading audio: \(fileName) (\(audioSize) bytes)")
            let mediaPath = try await service.uploadMedia(
                data: audioData,
                threadId: threadId,
                fileName: fileName,
                contentType: "audio/m4a"
            )
            let uploadDuration = Date().timeIntervalSince(uploadStartTime)
            print("✅ [RECALL-VIEWMODEL] [\(requestId)] Audio uploaded in \(String(format: "%.3f", uploadDuration))s: \(mediaPath)")
            
            // Insert user message
            let messageStartTime = Date()
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .voice,
                mediaPath: mediaPath
            )
            let messageDuration = Date().timeIntervalSince(messageStartTime)
            print("✅ [RECALL-VIEWMODEL] [\(requestId)] User message inserted in \(String(format: "%.3f", messageDuration))s: \(messageId.uuidString)")
            
            await loadMessages()
            
            // Insert status message
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching..."
            )
            
            await loadMessages()
            
            // Resolve
            let resolveStartTime = Date()
            print("🔍 [RECALL-VIEWMODEL] [\(requestId)] Calling resolveRecall:")
            print("   threadId: \(threadId.uuidString)")
            print("   messageId: \(messageId.uuidString)")
            print("   inputType: voice")
            print("   mediaPath: \(mediaPath)")
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .voice,
                mediaPath: mediaPath
            )
            let resolveDuration = Date().timeIntervalSince(resolveStartTime)
            print("✅ [RECALL-VIEWMODEL] [\(requestId)] resolveRecall completed in \(String(format: "%.3f", resolveDuration))s")
            print("📊 [RECALL-VIEWMODEL] [\(requestId)] Response: status=\(response.status), type=\(response.responseType ?? "nil"), candidates=\(response.candidates?.count ?? 0), hasAnswer=\(response.answer != nil)")
            
            // Update with candidate or answer
            if let assistantMessage = response.assistantMessage {
                print("📝 [RECALL-VIEWMODEL] [\(requestId)] Processing assistant message (candidate):")
                print("   title: \(assistantMessage.songTitle)")
                print("   artist: \(assistantMessage.songArtist)")
                print("   confidence: \(assistantMessage.confidence)")
                print("   reason: \(assistantMessage.reason.prefix(100))...")
                print("   sources: \(assistantMessage.sources.count)")
                
                let candidateJson: [String: AnyCodable] = [
                    "title": AnyCodable(assistantMessage.songTitle),
                    "artist": AnyCodable(assistantMessage.songArtist),
                    "confidence": AnyCodable(assistantMessage.confidence),
                    "reason": AnyCodable(assistantMessage.reason),
                    "lyric_snippet": AnyCodable(assistantMessage.lyricSnippet ?? "")
                ]
                
                let insertStartTime = Date()
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .candidate,
                    text: "\(assistantMessage.songTitle) by \(assistantMessage.songArtist)",
                    candidateJson: candidateJson,
                    sourcesJson: assistantMessage.sources,
                    confidence: assistantMessage.confidence,
                    songUrl: assistantMessage.songUrl,
                    songTitle: assistantMessage.songTitle,
                    songArtist: assistantMessage.songArtist
                )
                let insertDuration = Date().timeIntervalSince(insertStartTime)
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Candidate message inserted in \(String(format: "%.3f", insertDuration))s")
            } else if let answer = response.answer {
                print("📝 [RECALL-VIEWMODEL] [\(requestId)] Processing answer response:")
                print("   text length: \(answer.text.count) chars")
                print("   sources: \(answer.sources.count)")
                print("   related songs: \(answer.relatedSongs?.count ?? 0)")
                
                // Convert sources from [String] to [RecallSource] format
                let answerSources = answer.sources.enumerated().map { index, url in
                    RecallSource(
                        title: "Source \(index + 1)",
                        url: url,
                        snippet: nil,
                        publisher: nil
                    )
                }
                
                let insertStartTime = Date()
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .answer,
                    text: answer.text,
                    sourcesJson: answerSources
                )
                let insertDuration = Date().timeIntervalSince(insertStartTime)
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Answer message inserted in \(String(format: "%.3f", insertDuration))s")
            } else if let candidates = response.candidates, !candidates.isEmpty {
                print("📝 [RECALL-VIEWMODEL] [\(requestId)] Processing candidates array (\(candidates.count) candidates):")
                // Insert all candidates
                for (index, candidate) in candidates.enumerated() {
                    let candidateJson: [String: AnyCodable] = [
                        "title": AnyCodable(candidate.title),
                        "artist": AnyCodable(candidate.artist),
                        "confidence": AnyCodable(candidate.confidence),
                        "reason": AnyCodable(candidate.reason),
                        "lyric_snippet": AnyCodable(candidate.lyricSnippet ?? "")
                    ]
                    
                    let sources = candidate.sourceUrls.enumerated().map { idx, url in
                        RecallSource(
                            title: "Source \(idx + 1)",
                            url: url,
                            snippet: nil,
                            publisher: nil
                        )
                    }
                    
                    _ = try await service.insertMessage(
                        threadId: threadId,
                        role: .assistant,
                        messageType: .candidate,
                        text: "\(candidate.title) by \(candidate.artist)",
                        candidateJson: candidateJson,
                        sourcesJson: sources,
                        confidence: candidate.confidence,
                        songTitle: candidate.title,
                        songArtist: candidate.artist
                    )
                    print("   ✅ [\(index + 1)/\(candidates.count)] Inserted: \(candidate.title) by \(candidate.artist)")
                }
            } else {
                print("⚠️ [RECALL-VIEWMODEL] [\(requestId)] No assistant message, answer, or candidates in response")
            }
            
            await loadMessages()
            
            // Notify state machine that response was received
            stateMachine.handleEvent(.responseReceived)
            
            // Check for success - either candidate with confidence or answer
            if let confidence = response.assistantMessage?.confidence {
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Response received with confidence: \(confidence)")
                orbState = .done(confidence: confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        stateMachine.reset()
                        voiceOrchestrator.reset()
                        isVoiceModeActive = false
                    }
                }
            } else if response.answer != nil {
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Answer response received successfully")
                orbState = .done(confidence: 0.8) // High confidence for answers
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        stateMachine.reset()
                        voiceOrchestrator.reset()
                        isVoiceModeActive = false
                    }
                }
            } else if let candidates = response.candidates, !candidates.isEmpty {
                let topConfidence = candidates[0].confidence
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Candidates received, top confidence: \(topConfidence)")
                orbState = .done(confidence: topConfidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        stateMachine.reset()
                        voiceOrchestrator.reset()
                        isVoiceModeActive = false
                    }
                }
            } else {
                print("⚠️ [RECALL-VIEWMODEL] [\(requestId)] No valid response content (no assistantMessage, answer, or candidates)")
                orbState = .error
                stateMachine.handleEvent(.error(NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response received"])))
            }
            
            // Clean up recording file
            try? FileManager.default.removeItem(at: recordingURL)
            print("🗑️ [RECALL-VIEWMODEL] [\(requestId)] Recording file cleaned up")
            
            // Clear recording URL to allow new recordings
            voiceRecorder.recordingURL = nil
            
            // Reset state machine to idle after processing completes
            if stateMachine.currentState == .processing {
                stateMachine.reset()
            }
            voiceOrchestrator.reset()
            isVoiceModeActive = false

            let totalDuration = Date().timeIntervalSince(startTime)
            print("✅ [RECALL-VIEWMODEL] [\(requestId)] handleVoiceRecording() completed successfully in \(String(format: "%.3f", totalDuration))s")
            
        } catch {
            let totalDuration = Date().timeIntervalSince(startTime)
            errorMessage = "Failed to process voice: \(error.localizedDescription)"
            orbState = .error
            isProcessing = false
            stateMachine.handleEvent(.error(error))
            
            print("❌ [RECALL-VIEWMODEL] [\(requestId)] Failed to process voice after \(String(format: "%.3f", totalDuration))s: \(error.localizedDescription)")
            if let nsError = error as? NSError {
                print("   Error code: \(nsError.code), domain: \(nsError.domain)")
                print("   Error userInfo: \(nsError.userInfo)")
            }
            
            // Clear recording URL even on error
            voiceRecorder.recordingURL = nil
            
            // Reset state machine to allow recovery
            stateMachine.reset()
            voiceOrchestrator.reset()
            isVoiceModeActive = false
        }
    }
    
    private func handleVoiceResponse(_ response: RecallResolveResponse, messageId: UUID, threadId: UUID) async {
        let requestId = UUID().uuidString.prefix(8)
        isProcessing = false
        
        print("🔍 [RECALL-VIEWMODEL] [\(requestId)] handleVoiceResponse() called")
        print("📊 [RECALL-VIEWMODEL] [\(requestId)] Response: status=\(response.status), type=\(response.responseType ?? "nil"), candidates=\(response.candidates?.count ?? 0), hasAnswer=\(response.answer != nil), hasAssistantMessage=\(response.assistantMessage != nil)")
        
        do {
            // Update with answer or candidates only (never both assistantMessage and candidates to avoid duplicates)
            if let answer = response.answer {
                print("📝 [RECALL-VIEWMODEL] [\(requestId)] Processing answer response")
                // Convert sources from [String] to [RecallSource] format
                let answerSources = answer.sources.enumerated().map { index, url in
                    RecallSource(
                        title: "Source \(index + 1)",
                        url: url,
                        snippet: nil,
                        publisher: nil
                    )
                }
                
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .answer,
                    text: answer.text,
                    sourcesJson: answerSources
                )
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Answer message inserted")
            } else if let candidates = response.candidates, !candidates.isEmpty {
                print("📝 [RECALL-VIEWMODEL] [\(requestId)] Processing candidates array (\(candidates.count) candidates)")
                for candidate in candidates {
                    let candidateJson: [String: AnyCodable] = [
                        "title": AnyCodable(candidate.title),
                        "artist": AnyCodable(candidate.artist),
                        "confidence": AnyCodable(candidate.confidence),
                        "reason": AnyCodable(candidate.reason),
                        "lyric_snippet": AnyCodable(candidate.lyricSnippet ?? "")
                    ]
                    
                    let sources = candidate.sourceUrls.enumerated().map { idx, url in
                        RecallSource(
                            title: "Source \(idx + 1)",
                            url: url,
                            snippet: nil,
                            publisher: nil
                        )
                    }
                    
                    _ = try await service.insertMessage(
                        threadId: threadId,
                        role: .assistant,
                        messageType: .candidate,
                        text: "\(candidate.title) by \(candidate.artist)",
                        candidateJson: candidateJson,
                        sourcesJson: sources,
                        confidence: candidate.confidence,
                        songTitle: candidate.title,
                        songArtist: candidate.artist
                    )
                }
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] All candidates inserted")
            } else if let assistantMessage = response.assistantMessage {
                print("📝 [RECALL-VIEWMODEL] [\(requestId)] Processing single assistant message (candidate)")
                let candidateJson: [String: AnyCodable] = [
                    "title": AnyCodable(assistantMessage.songTitle),
                    "artist": AnyCodable(assistantMessage.songArtist),
                    "confidence": AnyCodable(assistantMessage.confidence),
                    "reason": AnyCodable(assistantMessage.reason),
                    "lyric_snippet": AnyCodable(assistantMessage.lyricSnippet ?? "")
                ]
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .candidate,
                    text: "\(assistantMessage.songTitle) by \(assistantMessage.songArtist)",
                    candidateJson: candidateJson,
                    sourcesJson: assistantMessage.sources,
                    confidence: assistantMessage.confidence,
                    songUrl: assistantMessage.songUrl,
                    songTitle: assistantMessage.songTitle,
                    songArtist: assistantMessage.songArtist
                )
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Single candidate message inserted")
            } else {
                print("⚠️ [RECALL-VIEWMODEL] [\(requestId)] No answer, candidates, or assistant message in response")
            }
            
            await loadMessages()
            
            // Notify state machine that response was received
            stateMachine.handleEvent(.responseReceived)
            
            // Check for success - either candidate with confidence or answer
            if let confidence = response.assistantMessage?.confidence {
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Response received with confidence: \(confidence)")
                orbState = .done(confidence: confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        stateMachine.reset()
                        voiceOrchestrator.reset()
                        isVoiceModeActive = false
                    }
                }
            } else if response.answer != nil {
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Answer response received successfully")
                orbState = .done(confidence: 0.8) // High confidence for answers
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        stateMachine.reset()
                        voiceOrchestrator.reset()
                        isVoiceModeActive = false
                    }
                }
            } else if let candidates = response.candidates, !candidates.isEmpty {
                let topConfidence = candidates[0].confidence
                print("✅ [RECALL-VIEWMODEL] [\(requestId)] Candidates received, top confidence: \(topConfidence)")
                orbState = .done(confidence: topConfidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        stateMachine.reset()
                    }
                }
            } else {
                print("⚠️ [RECALL-VIEWMODEL] [\(requestId)] No valid response content")
                orbState = .error
                stateMachine.handleEvent(.error(NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response received"])))
            }
            
            // Generate thread title if this is the first assistant response
            if let titleSuggestion = response.titleSuggestion {
                try? await RecallThreadTitleService.shared.generateTitle(threadId: threadId, titleSuggestion: titleSuggestion)
            }
        } catch {
            errorMessage = "Failed to handle response: \(error.localizedDescription)"
            Logger.recall.error("Failed to handle response: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Regenerate Answer
    
    func regenerateAnswer(messageId: UUID) async {
        guard let threadId = currentThreadId,
              let userMessage = messages.first(where: { $0.id == messageId && $0.role == .user }) else {
            return
        }
        
        isProcessing = true
        orbState = .thinking
        
        do {
            // Get the user's original text (prefer edited transcript, then raw, then text)
            let queryText = userMessage.editedTranscript ?? userMessage.rawTranscript ?? userMessage.text ?? ""
            
            // Insert status message
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Regenerating..."
            )
            
            await loadMessages()
            
            // Resolve with current thread context
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .text,
                text: queryText
            )
            
            await handleVoiceResponse(response, messageId: messageId, threadId: threadId)
        } catch {
            errorMessage = "Failed to regenerate answer: \(error.localizedDescription)"
            Logger.recall.error("Failed to regenerate answer: \(error.localizedDescription)")
            isProcessing = false
            orbState = .error
        }
    }
    
    // MARK: - Load Stash
    
    func loadStash() async -> [RecallStashItem] {
        do {
            return try await service.fetchStash()
        } catch {
            errorMessage = "Failed to load stash: \(error.localizedDescription)"
            print("❌ Failed to load stash: \(error)")
            return []
        }
    }
    
    // MARK: - Open Thread
    
    func openThread(threadId: UUID) async {
        currentThreadId = threadId
        await loadMessages()
    }
    
    // MARK: - Additional Methods for UI Integration
    
    func startNewSession(showWelcome: Bool = true) async {
        stopVoiceModeCapture()
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        voiceRecorder.recordingURL = nil
        voiceOrchestrator.reset()
        isVoiceModeActive = false

        currentThreadId = nil
        messages = []
        composerText = ""
        orbState = .idle
        errorMessage = nil
        isProcessing = false
        conversationMode = .idle
        pendingTranscript = nil
        stateMachine.reset()
        stateMachine.setLongPressBeganOnOrb(false)
        Logger.recall.info("Started new session")
        
        if showWelcome {
            await checkAndShowWelcomeOnAppOpen()
        } else {
            await startNewThreadIfNeeded()
        }
    }
    
    func cancelProcessing() {
        isProcessing = false
        orbState = .idle
        stateMachine.handleEvent(.cancel)
    }
    
    func terminateSession() {
        voiceModeExit()
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
        }
        voiceRecorder.recordingURL = nil

        currentThreadId = nil
        messages = []
        composerText = ""
        orbState = .idle
        errorMessage = nil
        isProcessing = false
        conversationMode = .idle
        pendingTranscript = nil
        stateMachine.reset()
        stateMachine.setLongPressBeganOnOrb(false)
        Logger.recall.info("Terminated session")
    }
    
    func confirmPendingTranscript() async {
        guard let pending = pendingTranscript else { return }
        // Mark as confirmed - in a full implementation, this would save the confirmation
        pendingTranscript = nil
        conversationMode = .idle
    }
    
    func declinePendingTranscript() async {
        // Decline and potentially reprompt
        pendingTranscript = nil
        conversationMode = .idle
    }
    
    func confirmCandidate(messageId: UUID, title: String, artist: String, url: String? = nil) async {
        guard let threadId = currentThreadId else { return }
        do {
            try await service.confirmRecall(recallId: messageId, title: title, artist: artist)
            try await service.addToStash(threadId: threadId, songTitle: title, songArtist: artist, confidence: nil)
            await loadMessages()
            Logger.recall.info("Confirmed and saved candidate: \(title) by \(artist)")
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            Logger.recall.error("confirmCandidate failed: \(error.localizedDescription)")
        }
    }
    
    func confirmAnswerResponse(messageId: UUID) async {
        await loadMessages()
        conversationMode = .idle
    }
    
    func dismissCandidate(messageId: UUID) {
        // Dismiss candidate - just update UI state
        print("❌ Dismissed candidate for message: \(messageId)")
    }
    
    func declineAnswerResponse(messageId: UUID) async {
        // Decline answer response and ask clarifying questions
        print("❌ Declined answer response for message: \(messageId)")
        // Could trigger a reprompt or ask for clarification
        conversationMode = .waitingForRefinement
    }
    
    func pickVideo(_ videoURL: URL) async {
        // Handle video selection - similar to image but for video
        // For now, treat as image input
        if let image = await extractThumbnail(from: videoURL) {
            await pickImage(image)
        }
    }
    
    private func extractThumbnail(from videoURL: URL) async -> UIImage? {
        // Extract thumbnail from video
        // This is a placeholder - would need AVFoundation implementation
        return nil
    }
    
    func createGreenRoomPost() async {
        // Create GreenRoom post - implementation depends on service
        showGreenRoomPrompt = false
        print("📝 Creating GreenRoom post")
    }
    
    func checkAndShowWelcomeOnAppOpen() async {
        // Only show welcome once per app session
        guard !hasShownWelcomeThisSession else {
            // Welcome already shown this session, just start thread without welcome
            await startNewThreadIfNeeded()
            return
        }
        
        // Create thread and show welcome message (new thread on app refresh)
        do {
            let threadId = try await service.createNewThread()
            currentThreadId = threadId
            
            // Insert welcome message
            let welcomeText = "Hi! I'm Recall. I can help you find songs, answer music questions, or recommend music based on your mood. What would you like to know?"
            
            let welcomeMessageId = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .text,
                text: welcomeText
            )
            
            // Mark welcome as shown for this session
            hasShownWelcomeThisSession = true
            
            // Load messages to display welcome
            await loadMessages()
            
            // Speak the welcome message
            VoiceResponseService.shared.speak(welcomeText)
            conversationMode = .speaking
            isSpeaking = true
            
            // Stop speaking indicator after message completes
            Task {
                try? await Task.sleep(nanoseconds: UInt64(welcomeText.count * 50_000_000)) // Rough estimate: 50ms per character
                isSpeaking = false
                conversationMode = .idle
            }
        } catch {
            errorMessage = "Failed to create thread: \(error.localizedDescription)"
            print("❌ Failed to create thread: \(error)")
        }
    }
    
    /// Reset welcome flag when app restarts (called from scenePhase change)
    func resetWelcomeFlag() {
        hasShownWelcomeThisSession = false
    }
    
    func reprompt(messageId: UUID, text: String) async {
        guard let threadId = currentThreadId else { return }
        lastUserQuery = text
        
        do {
            let newMessageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .text,
                text: text
            )
            
            await loadMessages()
            isProcessing = true
            orbState = .thinking
            
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: newMessageId,
                inputType: .text,
                text: text
            )
            
            // Handle response similar to sendText
            if let assistantMessage = response.assistantMessage {
                let candidateJson: [String: AnyCodable] = [
                    "title": AnyCodable(assistantMessage.songTitle),
                    "artist": AnyCodable(assistantMessage.songArtist),
                    "confidence": AnyCodable(assistantMessage.confidence),
                    "reason": AnyCodable(assistantMessage.reason),
                    "lyric_snippet": AnyCodable(assistantMessage.lyricSnippet ?? "")
                ]
                
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .candidate,
                    text: "\(assistantMessage.songTitle) by \(assistantMessage.songArtist)",
                    candidateJson: candidateJson,
                    sourcesJson: assistantMessage.sources,
                    confidence: assistantMessage.confidence,
                    songUrl: assistantMessage.songUrl,
                    songTitle: assistantMessage.songTitle,
                    songArtist: assistantMessage.songArtist
                )
            }
            
            await loadMessages()
            isProcessing = false
            
            if let confidence = response.assistantMessage?.confidence {
                orbState = .done(confidence: confidence)
                stateMachine.handleEvent(.responseReceived)
            } else {
                orbState = .error
            }
        } catch {
            errorMessage = "Failed to reprompt: \(error.localizedDescription)"
            isProcessing = false
            orbState = .error
            stateMachine.handleEvent(.error(error))
        }
    }
}














