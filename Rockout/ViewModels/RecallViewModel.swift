import Foundation
import SwiftUI
import Combine

@MainActor
final class RecallViewModel: ObservableObject {
    @Published var currentThreadId: UUID?
    @Published var messages: [RecallMessage] = []
    @Published var composerText: String = ""
    @Published var orbState: RecallOrbState = .idle
    @Published var selectedImage: UIImage?
    @Published var selectedVideoURL: URL?
    @Published var isResolving: Bool = false
    @Published var errorMessage: String?
    @Published var repromptingMessageId: UUID?
    @Published var showGreenRoomPrompt: Bool = false
    @Published var greenRoomPromptText: String = ""
    @Published var showRepromptSheet: Bool = false
    @Published var repromptMessageId: UUID?
    @Published var repromptOriginalQuery: String?
    @Published var pendingTranscript: (text: String, messageType: RecallMessageType, id: UUID)? // Track current speaking transcript
    @Published var confirmedMessageIds: Set<UUID> = [] // Track confirmed messages
    
    private let service = RecallService.shared
    var rejectionCount: Int = 0
    @Published var lastUserQuery: String? = nil
    private var lastUserMessageId: UUID? = nil
    private let voiceRecorder = VoiceRecorder()
    private let videoAudioExtractor = VideoAudioExtractor()
    private let voiceResponseService = VoiceResponseService.shared
    
    @Published var isSpeaking: Bool = false {
        didSet {
            print("🎤 [TRANSCRIPT] isSpeaking changed: \(isSpeaking)")
        }
    }
    @Published var conversationMode: ConversationMode = .idle {
        didSet {
            print("💬 [TRANSCRIPT] conversationMode changed: \(oldValue) -> \(conversationMode)")
            print("   - Messages count: \(messages.count)")
            if let lastMessage = messages.last {
                print("   - Last message type: \(lastMessage.messageType), hasText: \(lastMessage.text != nil)")
            }
        }
    }
    @Published var canTerminateSession: Bool = false
    @Published var isProcessing: Bool = false
    @Published var isReprompting: Bool = false
    
    // Task cancellation
    private var currentProcessingTask: Task<Void, Never>?
    
    enum ConversationMode {
        case idle
        case listening
        case processing
        case speaking
        case waitingForRefinement
    }
    
    private var shouldWaitForRefinement: Bool = false
    private var pendingFollowUpQuestion: String?
    private var currentSessionActive: Bool = false
    private var welcomeShownThisSession: Bool = false
    
    private var cancellables = Set<AnyCancellable>()
    
    // UserDefaults keys
    private let hasSeenWelcomeKey = "recall_has_seen_welcome"
    
    // Helper function to store spoken text as a message for transcript visibility
    // Only saves to database after confirmation
    private func storeSpokenMessage(_ text: String, messageType: RecallMessageType = .text) async {
        guard let threadId = currentThreadId else {
            print("🔴 [TRANSCRIPT] storeSpokenMessage: No threadId, cannot store message")
            return
        }
        print("📝 [TRANSCRIPT] storeSpokenMessage called:")
        print("   - Text: \(text.prefix(100))")
        print("   - MessageType: \(messageType)")
        print("   - ThreadId: \(threadId)")
        print("   - Current messages count before insert: \(messages.count)")
        do {
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: messageType,
                text: text
            )
            print("✅ [TRANSCRIPT] Message inserted successfully, ID: \(messageId)")
            // Mark as confirmed since we're saving it
            confirmedMessageIds.insert(messageId)
            await loadMessages()
            print("✅ [TRANSCRIPT] Messages reloaded after storing")
            print("   - Messages count after reload: \(messages.count)")
            if let lastMessage = messages.last {
                print("   - Last message: type=\(lastMessage.messageType), text=\(lastMessage.text?.prefix(50) ?? "nil")")
            }
        } catch {
            print("⚠️ [TRANSCRIPT] Failed to store spoken message: \(error)")
        }
    }
    
    // Store pending transcript (in memory only, not in database)
    private func setPendingTranscript(_ text: String, messageType: RecallMessageType) {
        let pendingId = UUID()
        pendingTranscript = (text: text, messageType: messageType, id: pendingId)
        print("📝 [TRANSCRIPT] Set pending transcript: \(text.prefix(50))... (ID: \(pendingId))")
    }
    
    // Confirm and save pending transcript to database
    func confirmPendingTranscript() async {
        guard let pending = pendingTranscript else {
            print("⚠️ [TRANSCRIPT] No pending transcript to confirm")
            return
        }
        print("✅ [TRANSCRIPT] Confirming pending transcript: \(pending.text.prefix(50))...")
        
        // Save to database
        let messageId = try? await service.insertMessage(
            threadId: currentThreadId!,
            role: .assistant,
            messageType: pending.messageType,
            text: pending.text
        )
        
        // Mark as confirmed
        if let messageId = messageId {
            confirmedMessageIds.insert(messageId)
        }
        
        // Clear pending transcript
        pendingTranscript = nil
        
        // Reload messages to show the confirmed message in chat
        await loadMessages()
        
        // Ensure UI updates on main thread to show saved message
        await MainActor.run {
            // Force UI refresh by accessing messages
            let _ = messages.count
        }
        
        // Speak confirmation message and save it immediately (no need for user to confirm the confirmation)
        let confirmationText = "Got it! I've saved that response. Is there anything else you'd like to know?"
        
        // Save confirmation message directly to database (no pending transcript needed)
        _ = try? await service.insertMessage(
            threadId: currentThreadId!,
            role: .assistant,
            messageType: .text,
            text: confirmationText
        )
        
        // Reload messages to show the confirmation
        await loadMessages()
        
        // Ensure UI updates on main thread to show confirmation message
        await MainActor.run {
            // Force UI refresh by accessing messages
            let _ = messages.count
        }
        
        // Set conversation mode to speaking so transcript is visible
        conversationMode = .speaking
        orbState = .idle
        
        // Speak the confirmation
        voiceResponseService.speak(confirmationText) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // After speaking confirmation, set to idle
                self.conversationMode = .idle
                self.orbState = .idle
            }
        }
        
        print("✅ [TRANSCRIPT] Transcript confirmed and saved to chat (message ID: \(messageId?.uuidString ?? "unknown"))")
    }
    
    // Decline pending transcript (don't save, clear it)
    func declinePendingTranscript() async {
        guard let pending = pendingTranscript else {
            print("⚠️ [TRANSCRIPT] No pending transcript to decline")
            return
        }
        print("❌ [TRANSCRIPT] Declining pending transcript: \(pending.text.prefix(50))...")
        pendingTranscript = nil
        
        // Re-answer the original query instead of just asking clarifying questions
        // This gives the user another chance with a potentially better answer
        if let messageId = lastUserMessageId, let threadId = currentThreadId {
            print("🔄 [TRANSCRIPT] Re-answering original query (messageId: \(messageId))")
            
            // Get the original user message to retry
            let userMessage = messages.first { $0.id == messageId }
            let inputType: RecallInputType = userMessage?.messageType == .voice ? .voice : .text
            let text = userMessage?.text
            let mediaPath = userMessage?.mediaPath
            
            orbState = .thinking
            conversationMode = .processing
            
            do {
                // Insert status message
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .status,
                    text: "Searching again..."
                )
                await loadMessages()
                
                // Resolve again with the original query
                let response = try await service.resolveRecall(
                    threadId: threadId,
                    messageId: messageId,
                    inputType: inputType,
                    text: text,
                    mediaPath: mediaPath
                )
                
                // Reload messages to get all candidates and answers inserted by edge function
                await loadMessages()
                
                // Handle answer-type responses
                if let answer = response.answer {
                    setPendingTranscript(answer.text, messageType: .answer)
                    conversationMode = .speaking
                    orbState = .idle
                    
                    // Speak the answer
                    voiceResponseService.speak(answer.text) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            // Keep conversation mode as .speaking until user confirms/declines
                        }
                    }
                } else if let candidates = response.candidates, !candidates.isEmpty {
                    // Handle candidates
                    orbState = .done(confidence: candidates.first?.confidence ?? 0.5)
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if case .done = orbState {
                            orbState = .idle
                        }
                    }
                } else {
                    // No answer or candidates - ask clarifying questions as fallback
                    await askClarifyingQuestions()
                }
            } catch {
                print("❌ [TRANSCRIPT] Failed to re-answer: \(error)")
                // Fallback to asking clarifying questions
                await askClarifyingQuestions()
            }
        } else {
            // No original query to retry - ask clarifying questions
            await askClarifyingQuestions()
        }
        
        print("❌ User declined pending transcript, re-answering original query")
    }
    
    init() {
        // Observe voice recorder state
        voiceRecorder.$isRecording
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if isRecording {
                    // State will be updated by meter level updates
                } else {
                    if case .listening = self.orbState {
                        // Recording stopped, will transition to thinking when upload starts
                    }
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
        
        // Observe TTS state
        voiceResponseService.$isSpeaking
            .sink { [weak self] (isSpeaking: Bool) in
                guard let self = self else { return }
                self.isSpeaking = isSpeaking
                if isSpeaking {
                    self.conversationMode = .speaking
                } else if self.conversationMode == .speaking {
                    // TTS finished, check if we should wait for refinement
                    if self.shouldWaitForRefinement {
                        self.conversationMode = .waitingForRefinement
                    } else {
                        self.conversationMode = .idle
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Thread Management
    
    func startNewThreadIfNeeded() async {
        do {
            let threadId = try await service.createThreadIfNeeded()
            currentThreadId = threadId
            currentSessionActive = true
            canTerminateSession = true
            await loadMessages()
        } catch {
            errorMessage = "Failed to create thread: \(error.localizedDescription)"
            print("❌ Failed to create thread: \(error)")
        }
    }
    
    // MARK: - Session Management
    
    func terminateSession() {
        // Cancel any ongoing processing
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        
        // Stop any ongoing TTS
        voiceResponseService.stopSpeaking()
        
        // Stop recording if active
        if voiceRecorder.isRecording {
            voiceRecorder.stopRecording()
        }
        
        // Reset conversation state
        shouldWaitForRefinement = false
        pendingFollowUpQuestion = nil
        conversationMode = .idle
        orbState = .idle
        isProcessing = false
        isResolving = false
        currentSessionActive = false
        canTerminateSession = false
        
        // Clear pending state
        rejectionCount = 0
        lastUserQuery = nil
        lastUserMessageId = nil
        
        // Keep thread and messages - user can continue or start new
        print("✅ Session terminated - user can continue or start new conversation")
    }
    
    func cancelProcessing() {
        // Cancel current processing task
        currentProcessingTask?.cancel()
        currentProcessingTask = nil
        
        // Stop TTS
        voiceResponseService.stopSpeaking()
        
        // Reset states
        isProcessing = false
        isResolving = false
        orbState = .idle
        conversationMode = .idle
        
        print("🛑 Processing cancelled by user")
    }
    
    func startNewSession(showWelcome: Bool = false) async {
        // Terminate current session first
        terminateSession()
        
        // Clear messages immediately for a fresh start visual
        messages = []
        
        // Reset all conversation flags
        lastUserQuery = nil
        lastUserMessageId = nil
        rejectionCount = 0
        shouldWaitForRefinement = false
        pendingFollowUpQuestion = nil
        isReprompting = false
        
        // Show thinking animation while creating new thread
        orbState = .thinking
        conversationMode = .processing
        
        // Wait a moment for the animation to show
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Create new thread (always create, don't reuse)
        do {
            let threadId = try await service.createNewThread()
            currentThreadId = threadId
            currentSessionActive = true
            canTerminateSession = true
            print("✅ New thread created: \(threadId)")
            
            // Haptic feedback for new thread
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.selectionChanged()
        } catch {
            errorMessage = "Failed to create new thread: \(error.localizedDescription)"
            print("❌ Failed to create new thread: \(error)")
            orbState = .error
            conversationMode = .idle
            return
        }
        
        // Reset to idle state
        orbState = .idle
        
        // Only show welcome message if:
        // 1. showWelcome is true (first app open or first time use)
        // 2. Welcome hasn't been shown in this session yet
        let shouldShowWelcome = showWelcome && !welcomeShownThisSession
        
        if shouldShowWelcome {
            // Mark welcome as shown
            welcomeShownThisSession = true
            UserDefaults.standard.set(true, forKey: hasSeenWelcomeKey)
        
        // Speak welcome message
        let welcomeMessage = "Hi! I'm Recall. I can help you find songs, answer music questions, explain what songs mean and interpret lyrics, or recommend music based on your mood. What would you like to know?"
            
            // Store the welcome message so transcript is visible for deaf users
            if let threadId = currentThreadId {
                do {
                    _ = try await service.insertMessage(
                        threadId: threadId,
                        role: .assistant,
                        messageType: .text,
                        text: welcomeMessage
                    )
                    await loadMessages()
                    
                    // Ensure UI updates on main thread to show welcome message
                    await MainActor.run {
                        // Force UI refresh by accessing messages
                        let _ = messages.count
                    }
                } catch {
                    print("⚠️ Failed to store welcome message: \(error)")
                }
            }
            
            conversationMode = .speaking
            voiceResponseService.speak(welcomeMessage) {
                Task { @MainActor in
                    self.conversationMode = .idle
                }
            }
        } else {
            conversationMode = .idle
        }
    }
    
    func checkAndShowWelcomeOnAppOpen() async {
        // Show welcome if:
        // 1. First time ever using Recall, OR
        // 2. App was just opened/refreshed (welcomeShownThisSession is false)
        let hasSeenWelcome = UserDefaults.standard.bool(forKey: hasSeenWelcomeKey)
        let shouldShowWelcome = !hasSeenWelcome || !welcomeShownThisSession
        
        if !currentSessionActive {
            await startNewSession(showWelcome: shouldShowWelcome)
        }
    }
    
    /// Ensures a thread exists before sending a message. Creates a new thread if currentThreadId is nil.
    func ensureThreadExists() async throws {
        if currentThreadId == nil {
            // Always create a new thread (don't reuse existing)
            let threadId = try await service.createNewThread()
            currentThreadId = threadId
            // Don't load messages - start fresh
            messages = []
        }
    }
    
    func loadMessages() async {
        guard let threadId = currentThreadId else {
            print("🔴 [TRANSCRIPT] loadMessages: No threadId")
            return
        }
        
        do {
            let loadedMessages = try await service.fetchMessages(threadId: threadId)
            print("📋 [TRANSCRIPT] loadMessages:")
            print("   - ThreadId: \(threadId)")
            print("   - Loaded \(loadedMessages.count) messages")
            for (index, msg) in loadedMessages.enumerated() {
                print("   - Message \(index): role=\(msg.role), type=\(msg.messageType), text=\(msg.text?.prefix(50) ?? "nil"), hasText=\(msg.text != nil && !msg.text!.isEmpty)")
            }
            
            // Update messages on main thread to ensure UI updates
            await MainActor.run {
                messages = loadedMessages
                print("✅ [TRANSCRIPT] Messages array updated on main thread, now has \(messages.count) messages")
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load messages: \(error.localizedDescription)"
            }
            print("❌ [TRANSCRIPT] Failed to load messages: \(error)")
        }
    }
    
    // MARK: - Send Text
    
    func sendText() async {
        guard !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        // Cancel any ongoing processing
        if isProcessing {
            cancelProcessing()
        }
        
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        composerText = ""
        
        // Cancel previous task and start new one
        currentProcessingTask?.cancel()
        currentProcessingTask = Task {
            do {
                // Ensure thread exists before sending
                try await ensureThreadExists()
                guard let threadId = currentThreadId else {
                    errorMessage = "Failed to create thread"
                    return
                }
                
                // Check if cancelled
                guard !Task.isCancelled else { return }
                
                // Insert user message
                let messageId = try await service.insertMessage(
                    threadId: threadId,
                    role: .user,
                    messageType: .text,
                    text: text
                )
                
                // Track for retry logic
                lastUserQuery = text
                lastUserMessageId = messageId
                rejectionCount = 0
                
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
                isProcessing = true
                orbState = .thinking
                
                // Check if cancelled
                guard !Task.isCancelled else {
                    print("🛑 [SEND-TEXT] Cancelled before resolveRecall")
                    isProcessing = false
                    return
                }
                
                // Resolve (edge function now inserts all candidates directly)
                let resolveStartTime = Date()
                print("🔍 [SEND-TEXT] Calling resolveRecall at \(resolveStartTime)")
                print("📋 [SEND-TEXT] Input: text=\"\(text.prefix(50))...\", threadId=\(threadId), messageId=\(messageId)")
                isResolving = true
                let response = try await service.resolveRecall(
                    threadId: threadId,
                    messageId: messageId,
                    inputType: .text,
                    text: text
                )
                let resolveTime = Date().timeIntervalSince(resolveStartTime)
                print("⏱️ [SEND-TEXT] resolveRecall completed in \(resolveTime)s")
                print("📊 [SEND-TEXT] Response: status=\(response.status), type=\(response.responseType ?? "none"), candidates=\(response.candidates?.count ?? 0), has_answer=\(response.answer != nil)")
                
                // Check if cancelled after processing
                guard !Task.isCancelled else {
                    print("🛑 [SEND-TEXT] Cancelled after resolveRecall")
                    isProcessing = false
                    isResolving = false
                    return
                }
                
                isResolving = false
                
                // Reload messages to get all candidates inserted by edge function
                await loadMessages()
                
                // Handle answer-type responses (text input can also be questions)
                if let answer = response.answer {
                print("📝 Answer response received: \(answer.text.prefix(50))...")
                
                // Reload messages to get the answer message inserted by edge function
                await loadMessages()
                
                // Verify the answer message is in the messages array
                // Check for both .answer type and assistant .text type (edge function may use either)
                let answerMessages = messages.filter { msg in
                    (msg.messageType == .answer || (msg.messageType == .text && msg.role == .assistant)) &&
                    msg.text == answer.text
                }
                print("🔍 [TRANSCRIPT] Found \(answerMessages.count) answer messages matching response")
                print("   - Looking for text: \(answer.text.prefix(50))")
                for (idx, msg) in answerMessages.enumerated() {
                    print("   - Answer \(idx): type=\(msg.messageType), text=\(msg.text?.prefix(50) ?? "nil")")
                }
                
                // Set pending transcript (in memory only, not saved yet)
                setPendingTranscript(answer.text, messageType: .answer)
                
                // Set conversation mode to speaking so transcript is visible
                print("🎤 [TRANSCRIPT] Setting conversationMode to .speaking")
                print("   - Current messages count: \(messages.count)")
                conversationMode = .speaking
                print("✅ [TRANSCRIPT] conversationMode is now: \(conversationMode)")
                orbState = .idle
                
                // Speak the answer
                voiceResponseService.speak(answer.text) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        // After TTS completes, check for follow-up
                        if let followUp = response.followUpQuestion {
                            self.shouldWaitForRefinement = true
                            self.conversationMode = .waitingForRefinement
                            self.voiceResponseService.speak(followUp) { [weak self] in
                                Task { @MainActor [weak self] in
                                    guard let self = self else { return }
                                    self.conversationMode = .waitingForRefinement
                                    self.orbState = .idle
                                }
                            }
                        } else {
                            self.orbState = .idle
                            self.conversationMode = .idle
                        }
                    }
                }
                
                    isProcessing = false
                    return
                }
                
                // Check for follow-up question
                if let followUpQuestion = response.followUpQuestion {
                print("💬 Follow-up question received: \(followUpQuestion)")
                pendingFollowUpQuestion = followUpQuestion
                shouldWaitForRefinement = true
                conversationMode = .waitingForRefinement
                
                // Speak the follow-up question
                voiceResponseService.speak(followUpQuestion) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.conversationMode = .waitingForRefinement
                        self.orbState = .idle
                    }
                }
                
                    orbState = .idle
                    isProcessing = false
                    return
                }
                
                // Update orb state based on top candidate confidence
                if let candidates = response.candidates, !candidates.isEmpty {
                let topCandidate = candidates.first!
                
                // Always speak the result in a conversational way
                let resultText: String
                if candidates.count == 1 {
                    resultText = "I found \(topCandidate.title) by \(topCandidate.artist)."
                } else {
                    resultText = "I found \(candidates.count) matches. The top match is \(topCandidate.title) by \(topCandidate.artist)."
                }
                
                    // Set pending transcript (in memory only, not saved yet)
                    setPendingTranscript(resultText, messageType: .answer)
                    
                    // Set conversation mode to speaking so transcript is visible
                    print("🎤 [TRANSCRIPT] Setting conversationMode to .speaking")
                    conversationMode = .speaking
                    print("✅ [TRANSCRIPT] conversationMode is now: \(conversationMode)")
                    
                    print("🔊 [TRANSCRIPT] Starting to speak resultText: \(resultText.prefix(50))")
                    voiceResponseService.speak(resultText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        print("🔇 [TRANSCRIPT] Finished speaking resultText")
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                    orbState = .done(confidence: topCandidate.confidence)
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if case .done = orbState {
                            orbState = .idle
                        }
                    }
                } else if let assistantMessage = response.assistantMessage {
                    print("✅ Using assistantMessage: \(assistantMessage.songTitle) by \(assistantMessage.songArtist)")
                    
                    // Speak the result
                    let resultText = "I found \(assistantMessage.songTitle) by \(assistantMessage.songArtist)."
                    
                    // Set pending transcript (in memory only, not saved yet)
                    setPendingTranscript(resultText, messageType: .answer)
                    
                    // Set conversation mode to speaking so transcript is visible
                    conversationMode = .speaking
                    
                    voiceResponseService.speak(resultText) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.orbState = .idle
                            self.conversationMode = .idle
                        }
                    }
                    
                    orbState = .done(confidence: assistantMessage.confidence)
                    
                    // Reset to idle after 2 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if case .done = orbState {
                            orbState = .idle
                        }
                    }
                } else {
                    print("❌ No results found for text query")
                    
                    // Haptic feedback for no results
                    let notificationFeedback = UINotificationFeedbackGenerator()
                    notificationFeedback.notificationOccurred(.warning)
                    
                    // Audio announcement for VoiceOver
                    UIAccessibility.post(notification: .announcement, argument: "No results found")
                    
                    // Speak error message
                    let errorText = "I couldn't find anything matching your search. Could you try rephrasing?"
                    
                    // Store the spoken error as a message so transcript is visible for deaf users
                    await storeSpokenMessage(errorText)
                    
                    voiceResponseService.speak(errorText) { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.orbState = .idle
                            self.conversationMode = .idle
                        }
                    }
                    
                    orbState = .error
                }
                
                isProcessing = false
            } catch {
                isProcessing = false
                errorMessage = "Failed to send message: \(error.localizedDescription)"
                
                // Speak error message
                let errorVoiceText = "Sorry, I encountered an error processing your text. Please try again."
                
                // Store the spoken error as a message so transcript is visible for deaf users
                await storeSpokenMessage(errorVoiceText)
                
                voiceResponseService.speak(errorVoiceText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                orbState = .error
                print("❌ Failed to send text: \(error)")
            }
        }
    }
    
    // MARK: - Pick Image
    
    func pickImage(_ image: UIImage) async {
        selectedImage = image
        await sendImage()
    }
    
    // MARK: - Pick Video
    
    func pickVideo(_ videoURL: URL) async {
        selectedVideoURL = videoURL
        await sendVideo()
    }
    
    private func sendVideo() async {
        guard let videoURL = selectedVideoURL else {
            return
        }
        
        selectedVideoURL = nil
        
        do {
            // Ensure thread exists before sending
            try await ensureThreadExists()
            guard let threadId = currentThreadId else {
                errorMessage = "Failed to create thread"
                return
            }
            
            // Extract audio from video
            let audioURL = try await videoAudioExtractor.extractAudio(from: videoURL)
            let audioData = try Data(contentsOf: audioURL)
            
            // Upload video
            let videoData = try Data(contentsOf: videoURL)
            let videoFileName = "video_\(Int(Date().timeIntervalSince1970)).mov"
            let videoPath = try await service.uploadMedia(
                data: videoData,
                threadId: threadId,
                fileName: videoFileName,
                contentType: "video/quicktime"
            )
            
            // Upload extracted audio
            let audioFileName = "audio_\(Int(Date().timeIntervalSince1970)).m4a"
            let audioPath = try await service.uploadMedia(
                data: audioData,
                threadId: threadId,
                fileName: audioFileName,
                contentType: "audio/m4a"
            )
            
            // Insert user message with video path
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .image, // Using image type for now, could add .video
                mediaPath: videoPath
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
            
            // Resolve with video and audio paths
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .image, // Using image for now, edge function handles video_path
                mediaPath: videoPath,
                audioPath: audioPath,
                videoPath: videoPath
            )
            
            // Reload messages to get all candidates inserted by edge function
            await loadMessages()
            
            // Update orb state and speak results
            if let candidates = response.candidates, !candidates.isEmpty {
                let topCandidate = candidates.first!
                
                // Speak the result
                let resultText: String
                if candidates.count == 1 {
                    resultText = "I found \(topCandidate.title) by \(topCandidate.artist)."
                } else {
                    resultText = "I found \(candidates.count) matches. The top match is \(topCandidate.title) by \(topCandidate.artist)."
                }
                
                // Set pending transcript (in memory only, not saved yet)
                setPendingTranscript(resultText, messageType: .answer)
                
                // Set conversation mode to speaking so transcript is visible
                print("🎤 [TRANSCRIPT] Setting conversationMode to .speaking")
                conversationMode = .speaking
                print("✅ [TRANSCRIPT] conversationMode is now: \(conversationMode)")
                
                print("🔊 [TRANSCRIPT] Starting to speak resultText: \(resultText.prefix(50))")
                voiceResponseService.speak(resultText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        print("🔇 [TRANSCRIPT] Finished speaking resultText")
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                orbState = .done(confidence: topCandidate.confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                    }
                }
            } else if let assistantMessage = response.assistantMessage {
                // Speak the result
                let resultText = "I found \(assistantMessage.songTitle) by \(assistantMessage.songArtist)."
                
                // Set pending transcript (in memory only, not saved yet)
                setPendingTranscript(resultText, messageType: .answer)
                
                // Set conversation mode to speaking so transcript is visible
                print("🎤 [TRANSCRIPT] Setting conversationMode to .speaking")
                conversationMode = .speaking
                print("✅ [TRANSCRIPT] conversationMode is now: \(conversationMode)")
                
                print("🔊 [TRANSCRIPT] Starting to speak resultText: \(resultText.prefix(50))")
                voiceResponseService.speak(resultText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        print("🔇 [TRANSCRIPT] Finished speaking resultText")
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                orbState = .done(confidence: assistantMessage.confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                    }
                }
            } else {
                // Speak error message
                let errorText = "I couldn't identify the song from this video. Could you try again with a clearer recording?"
                
                // Store the spoken error as a message so transcript is visible for deaf users
                await storeSpokenMessage(errorText)
                
                voiceResponseService.speak(errorText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                orbState = .error
            }
            
            // Clean up temporary files
            try? FileManager.default.removeItem(at: videoURL)
            try? FileManager.default.removeItem(at: audioURL)
            
        } catch {
            errorMessage = "Failed to send video: \(error.localizedDescription)"
            
            // Speak error message
            let errorVoiceText = "Sorry, I encountered an error processing your video. Please try again."
            
            // Store the spoken error as a message so transcript is visible for deaf users
            await storeSpokenMessage(errorVoiceText)
            
            voiceResponseService.speak(errorVoiceText) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.orbState = .idle
                    self.conversationMode = .idle
                }
            }
            
            orbState = .error
            print("❌ Failed to send video: \(error)")
        }
    }
    
    private func sendImage() async {
        guard let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.7) else {
            return
        }
        
        selectedImage = nil
        
        do {
            // Ensure thread exists before sending
            try await ensureThreadExists()
            guard let threadId = currentThreadId else {
                errorMessage = "Failed to create thread"
                return
            }
            
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
            
            // Track for retry logic
            lastUserQuery = "Image search"
            lastUserMessageId = messageId
            rejectionCount = 0
            
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
            
            // Resolve (edge function now inserts all candidates directly)
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .image,
                mediaPath: mediaPath
            )
            
            // Reload messages to get all candidates inserted by edge function
            await loadMessages()
            
            // Update orb state and speak results
            if let candidates = response.candidates, !candidates.isEmpty {
                let topCandidate = candidates.first!
                
                // Speak the result
                let resultText: String
                if candidates.count == 1 {
                    resultText = "I found \(topCandidate.title) by \(topCandidate.artist)."
                } else {
                    resultText = "I found \(candidates.count) matches. The top match is \(topCandidate.title) by \(topCandidate.artist)."
                }
                
                // Set pending transcript (in memory only, not saved yet)
                setPendingTranscript(resultText, messageType: .answer)
                
                // Set conversation mode to speaking so transcript is visible
                print("🎤 [TRANSCRIPT] Setting conversationMode to .speaking")
                conversationMode = .speaking
                print("✅ [TRANSCRIPT] conversationMode is now: \(conversationMode)")
                
                print("🔊 [TRANSCRIPT] Starting to speak resultText: \(resultText.prefix(50))")
                voiceResponseService.speak(resultText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        print("🔇 [TRANSCRIPT] Finished speaking resultText")
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                orbState = .done(confidence: topCandidate.confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                    }
                }
            } else if let assistantMessage = response.assistantMessage {
                // Speak the result
                let resultText = "I found \(assistantMessage.songTitle) by \(assistantMessage.songArtist)."
                
                // Set pending transcript (in memory only, not saved yet)
                setPendingTranscript(resultText, messageType: .answer)
                
                // Set conversation mode to speaking so transcript is visible
                print("🎤 [TRANSCRIPT] Setting conversationMode to .speaking")
                conversationMode = .speaking
                print("✅ [TRANSCRIPT] conversationMode is now: \(conversationMode)")
                
                print("🔊 [TRANSCRIPT] Starting to speak resultText: \(resultText.prefix(50))")
                voiceResponseService.speak(resultText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        print("🔇 [TRANSCRIPT] Finished speaking resultText")
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                orbState = .done(confidence: assistantMessage.confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                    }
                }
            } else {
                // Speak error message
                let errorText = "I couldn't identify the song from this image. Could you try a different image or screenshot?"
                
                // Store the spoken error as a message so transcript is visible for deaf users
                await storeSpokenMessage(errorText)
                
                voiceResponseService.speak(errorText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                orbState = .error
            }
            
        } catch {
            errorMessage = "Failed to send image: \(error.localizedDescription)"
            
            // Speak error message
            let errorVoiceText = "Sorry, I encountered an error processing your image. Please try again."
            
            // Store the spoken error as a message so transcript is visible for deaf users
            await storeSpokenMessage(errorVoiceText)
            
            voiceResponseService.speak(errorVoiceText) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.orbState = .idle
                    self.conversationMode = .idle
                }
            }
            
            orbState = .error
            print("❌ Failed to send image: \(error)")
        }
    }
    
    // MARK: - Orb Long Press
    
    func orbLongPressed() async {
        // Start recording on long press
        guard !voiceRecorder.isRecording else { return }
        
        // Stop TTS if speaking
        if voiceResponseService.isSpeaking {
            voiceResponseService.stopSpeaking()
        }
        
        // Check if there's a previous query to reprompt
        // If we have messages and a last user query, this is a reprompt
        // Also check if there are any confirmed assistant messages (user can reprompt those)
        let hasPreviousQuery = !messages.isEmpty && lastUserQuery != nil && lastUserMessageId != nil
        
        // Find the last confirmed assistant message to use as reprompt context
        let lastConfirmedMessage = messages.filter { $0.role == .assistant && confirmedMessageIds.contains($0.id) }.last
        let hasConfirmedMessages = lastConfirmedMessage != nil
        
        // If reprompting with a confirmed message, set the context
        if hasConfirmedMessages, let confirmedMsg = lastConfirmedMessage {
            // Use the confirmed message's text as the reprompt context
            lastUserQuery = confirmedMsg.text ?? "Previous response"
            // Find the user message that preceded this confirmed message for context
            if let confirmedIndex = messages.firstIndex(where: { $0.id == confirmedMsg.id }) {
                let precedingMessages = Array(messages[..<confirmedIndex])
                if let precedingUserMessage = precedingMessages.last(where: { $0.role == .user }) {
                    lastUserMessageId = precedingUserMessage.id
                }
            }
        }
        
        // Allow reprompt if there's a previous query OR if there are confirmed messages
        isReprompting = (hasPreviousQuery || hasConfirmedMessages) && !shouldWaitForRefinement
        
        // If we're waiting for refinement (follow-up question), we're continuing the conversation
        // Reset the flag when user starts responding
        if shouldWaitForRefinement {
            shouldWaitForRefinement = false
            pendingFollowUpQuestion = nil
            isReprompting = false // Not a reprompt, just continuing conversation
            // Haptic feedback when responding to follow-up question
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        } else if isReprompting {
            // Haptic feedback for reprompt
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
        
        do {
            conversationMode = .listening
            try await voiceRecorder.startRecording()
            orbState = .listening(level: 0.0)
            
            // Haptic feedback for recording started
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // Audio announcement for VoiceOver
            UIAccessibility.post(notification: .announcement, argument: "Recording started")
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            orbState = .error
            conversationMode = .idle
            isReprompting = false
            print("❌ Failed to start recording: \(error)")
        }
    }
    
    func orbLongPressEnded() async {
        // Stop recording IMMEDIATELY on release - ensure it stops regardless of state
        print("🛑 [LONG_PRESS] Long press ended - stopping recording if active")
        
        // ALWAYS stop recording when gesture ends - this is critical
        // Even if isRecording is false, call stopRecording() to ensure cleanup
        if voiceRecorder.isRecording {
            print("🛑 [LONG_PRESS] Recording is active, stopping immediately...")
            voiceRecorder.stopRecording()
            
            // Update orb state immediately to reflect that recording has stopped
            if case .listening = orbState {
                orbState = .thinking
            }
            
            conversationMode = .processing
            
            // Haptic feedback for recording stopped
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            // Audio announcement for VoiceOver
            UIAccessibility.post(notification: .announcement, argument: "Recording stopped, processing your query")
            
            // Cancel any previous processing
            currentProcessingTask?.cancel()
            
            // Start new processing task
            currentProcessingTask = Task {
                await handleVoiceRecording()
            }
        } else {
            // Recording wasn't active, but ensure orb state is correct
            print("🛑 [LONG_PRESS] Recording was not active, ensuring orb state is correct")
            
            // Force stop anyway to ensure cleanup (idempotent operation)
            voiceRecorder.stopRecording()
            
            // Update orb state if it's still in listening mode
            if case .listening = orbState {
                orbState = .idle
            }
            
            // Reset conversation mode if needed
            if conversationMode == .processing && !isProcessing {
                conversationMode = .idle
            }
        }
        
        print("✅ [LONG_PRESS] Long press ended handling complete - recording stopped")
    }
    
    private func handleVoiceRecording() async {
        // Check if cancelled
        guard !Task.isCancelled else {
            print("🛑 Voice recording processing cancelled")
            return
        }
        
        guard let recordingURL = voiceRecorder.recordingURL else {
            orbState = .error
            return
        }
        
        // Add a small delay to allow audio session to fully transition
        // from recording to playback mode
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        print("✅ Audio session transition delay complete")
        
        isProcessing = true
        orbState = .thinking
        
        do {
            // Ensure thread exists before sending
            try await ensureThreadExists()
            guard let threadId = currentThreadId else {
                errorMessage = "Failed to create thread"
                orbState = .error
                return
            }
            
            // Read audio data
            let audioData = try Data(contentsOf: recordingURL)
            
            // Upload
            let fileName = "voice_\(Int(Date().timeIntervalSince1970)).m4a"
            let mediaPath = try await service.uploadMedia(
                data: audioData,
                threadId: threadId,
                fileName: fileName,
                contentType: "audio/m4a"
            )
            
            // #region agent log
            let preInsertLog: [String: Any] = [
                "location": "RecallViewModel.handleVoiceRecording:preInsert",
                "message": "About to insert user voice message",
                "threadId": threadId.uuidString,
                "mediaPath": mediaPath,
                "timestamp": Date().timeIntervalSince1970
            ]
            if let url = URL(string: "http://127.0.0.1:7242/ingest/ddc3f234-aa2d-49ac-904f-551be17c38c3"),
               let jsonData = try? JSONSerialization.data(withJSONObject: preInsertLog) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData
                _ = try? await URLSession.shared.data(for: request)
            }
            // #endregion
            
            // Insert user message
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .voice,
                mediaPath: mediaPath
            )
            
            // #region agent log
            let postInsertLog: [String: Any] = [
                "location": "RecallViewModel.handleVoiceRecording:postInsert",
                "message": "User message inserted successfully",
                "messageId": messageId.uuidString,
                "timestamp": Date().timeIntervalSince1970
            ]
            if let url = URL(string: "http://127.0.0.1:7242/ingest/ddc3f234-aa2d-49ac-904f-551be17c38c3"),
               let jsonData = try? JSONSerialization.data(withJSONObject: postInsertLog) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData
                _ = try? await URLSession.shared.data(for: request)
            }
            // #endregion
            
            // Track for retry logic
            // If reprompting, keep the original query context, otherwise update
            if !isReprompting {
            lastUserQuery = "Voice note"
            lastUserMessageId = messageId
            }
            // Note: If reprompting, lastUserMessageId should already be set to the original message
            rejectionCount = 0
            
            await loadMessages()
            
            // Insert status message
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching..."
            )
            
            await loadMessages()
            
            // Resolve (edge function now inserts all candidates directly)
            print("🔍 Calling resolveRecall with threadId: \(threadId), messageId: \(messageId), mediaPath: \(mediaPath)")
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .voice,
                mediaPath: mediaPath
            )
            
            print("✅ resolveRecall returned: status=\(response.status), responseType=\(response.responseType ?? "none"), candidates=\(response.candidates?.count ?? 0), answer=\(response.answer != nil ? "present" : "nil"), assistantMessage=\(response.assistantMessage != nil ? "present" : "nil")")
            
            // Update user message with transcription if available
            if let transcription = response.transcription, !transcription.isEmpty {
                print("📝 Transcription received: \"\(transcription)\"")
                // Update the user message with transcription
                try? await service.updateMessage(
                    messageId: messageId,
                    text: transcription
                )
                lastUserQuery = transcription
            }
            
            // Reload messages to get all candidates and answers inserted by edge function
            await loadMessages()
            
            // Handle answer-type responses
            if let answer = response.answer {
                print("📝 Answer response received: \(answer.text.prefix(50))...")
                
                // Ensure messages are loaded and visible before speaking
                // Add a small delay to ensure edge function has finished inserting the answer message
                await loadMessages()
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                await loadMessages()
                
                // Find the answer message that matches what we're about to speak
                let answerMessage = messages.first { msg in
                    (msg.messageType == .answer || msg.messageType == .text) &&
                    msg.role == .assistant &&
                    msg.text?.trimmingCharacters(in: .whitespacesAndNewlines) == answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                print("🎤 [TRANSCRIPT] Setting conversationMode to .speaking")
                print("   - Current messages count: \(messages.count)")
                print("   - Answer message found: \(answerMessage != nil)")
                print("   - Answer message ID: \(answerMessage?.id.uuidString ?? "none")")
                print("   - Answer message text: \(answerMessage?.text?.prefix(50) ?? "none")")
                print("   - Answer to speak: \(answer.text.prefix(50))")
                
                // Set pending transcript (in memory only, not saved yet)
                setPendingTranscript(answer.text, messageType: .answer)
                
                // Set conversation mode to speaking so transcript is visible
                conversationMode = .speaking
                print("✅ [TRANSCRIPT] conversationMode is now: \(conversationMode)")
                orbState = .idle
                
                // Speak the answer
                voiceResponseService.speak(answer.text) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        // After TTS completes, check for follow-up
                        if let followUp = response.followUpQuestion {
                            self.shouldWaitForRefinement = true
                            self.conversationMode = .waitingForRefinement
                            // Set pending transcript for follow-up (not saved yet)
                            self.setPendingTranscript(followUp, messageType: .follow_up)
                            self.conversationMode = .speaking
                            self.voiceResponseService.speak(followUp) { [weak self] in
                                Task { @MainActor [weak self] in
                                    guard let self = self else { return }
                                    self.conversationMode = .waitingForRefinement
                                    self.orbState = .idle
                                }
                            }
                        } else {
                            self.orbState = .idle
                            self.conversationMode = .idle
                        }
                    }
                }
                
                return
            }
            
            // Check for follow-up question first (conversational flow)
            if let followUpQuestion = response.followUpQuestion {
                print("💬 Follow-up question received: \(followUpQuestion)")
                pendingFollowUpQuestion = followUpQuestion
                shouldWaitForRefinement = true
                conversationMode = .waitingForRefinement
                
                // Set pending transcript (in memory only, not saved yet)
                setPendingTranscript(followUpQuestion, messageType: .follow_up)
                conversationMode = .speaking
                
                // Speak the follow-up question
                voiceResponseService.speak(followUpQuestion) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        // After TTS completes, enable recording for user response
                        self.conversationMode = .waitingForRefinement
                        // Visual cue that user can speak
                        self.orbState = .idle
                    }
                }
                
                orbState = .idle
                return
            }
            
            // Check for candidates first (edge function returns top 5)
            if let candidates = response.candidates, !candidates.isEmpty {
                let topCandidate = candidates.first!
                print("✅ Found \(candidates.count) candidates, top confidence: \(topCandidate.confidence)")
                
                // Haptic feedback for success
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
                
                // Audio announcement for VoiceOver
                let announcement = candidates.count == 1 ? "Found 1 result" : "Found \(candidates.count) results"
                UIAccessibility.post(notification: .announcement, argument: announcement)
                
                // Reset conversation refinement state since we found results
                shouldWaitForRefinement = false
                pendingFollowUpQuestion = nil
                
                // Always speak the result in a conversational way
                let resultText: String
                if candidates.count == 1 {
                    resultText = "I found \(topCandidate.title) by \(topCandidate.artist)."
                } else {
                    resultText = "I found \(candidates.count) matches. The top match is \(topCandidate.title) by \(topCandidate.artist)."
                }
                print("🔊 [TRANSCRIPT] Starting to speak resultText: \(resultText.prefix(50))")
                voiceResponseService.speak(resultText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        print("🔇 [TRANSCRIPT] Finished speaking resultText")
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                orbState = .done(confidence: topCandidate.confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        conversationMode = .idle
                    }
                }
            } else if let assistantMessage = response.assistantMessage {
                print("✅ Using assistantMessage: \(assistantMessage.songTitle) by \(assistantMessage.songArtist)")
                
                // Reset conversation refinement state
                shouldWaitForRefinement = false
                pendingFollowUpQuestion = nil
                
                // Speak the result using assistantMessage data
                let resultText = "I found \(assistantMessage.songTitle) by \(assistantMessage.songArtist)."
                
                // Store the spoken result as a message so transcript is visible for deaf users
                do {
                    _ = try await service.insertMessage(
                        threadId: threadId,
                        role: .assistant,
                        messageType: .text,
                        text: resultText
                    )
                    await loadMessages()
                } catch {
                    print("⚠️ Failed to store result message: \(error)")
                }
                
                print("🔊 [TRANSCRIPT] Starting to speak resultText: \(resultText.prefix(50))")
                voiceResponseService.speak(resultText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        print("🔇 [TRANSCRIPT] Finished speaking resultText")
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                orbState = .done(confidence: assistantMessage.confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                        conversationMode = .idle
                    }
                }
            } else {
                print("❌ No candidates, answer, or assistantMessage found in response")
                
                // Speak error message to user
                let errorText = "I couldn't find a match. Could you try humming or singing a bit more of the song?"
                
                // Store the spoken error as a message so transcript is visible for deaf users
                await storeSpokenMessage(errorText)
                
                voiceResponseService.speak(errorText) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.orbState = .idle
                        self.conversationMode = .idle
                    }
                }
                
                // Reset conversation refinement state on error
                shouldWaitForRefinement = false
                pendingFollowUpQuestion = nil
                isReprompting = false
                orbState = .error
                conversationMode = .idle
            }
            
                // Clean up recording file
                try? FileManager.default.removeItem(at: recordingURL)
                
                // Reset reprompting flag after processing completes
                isReprompting = false
                isProcessing = false
            } catch {
                isProcessing = false
                // #region agent log
            var errorLog: [String: Any] = [
                "location": "RecallViewModel.handleVoiceRecording:catch",
                "message": "Voice processing failed",
                "error": error.localizedDescription,
                "errorType": String(describing: type(of: error)),
                "timestamp": Date().timeIntervalSince1970
            ]
            if let nsError = error as? NSError {
                errorLog["errorCode"] = nsError.code
                errorLog["errorDomain"] = nsError.domain
                errorLog["errorUserInfo"] = nsError.userInfo
            }
            if let url = URL(string: "http://127.0.0.1:7242/ingest/ddc3f234-aa2d-49ac-904f-551be17c38c3"),
               let jsonData = try? JSONSerialization.data(withJSONObject: errorLog) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData
                _ = try? await URLSession.shared.data(for: request)
            }
            // #endregion
            
            let errorDesc = error.localizedDescription
            errorMessage = "Failed to process voice: \(errorDesc)"
            
            // Speak error message to user
            let errorVoiceText = "Sorry, I encountered an error while processing your request. Please try again."
            
            // Store the spoken error as a message so transcript is visible for deaf users
            await storeSpokenMessage(errorVoiceText)
            
            voiceResponseService.speak(errorVoiceText) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.orbState = .idle
                    self.conversationMode = .idle
                }
            }
            
            isReprompting = false
            orbState = .error
            print("❌ Failed to process voice: \(error)")
            print("   Error type: \(type(of: error))")
            if let nsError = error as? NSError {
                print("   Error code: \(nsError.code)")
                print("   Error domain: \(nsError.domain)")
                print("   Error userInfo: \(nsError.userInfo)")
            }
            // Check if it's an RLS error
            if errorDesc.contains("row-level security") || errorDesc.contains("RLS") {
                print("⚠️ RLS ERROR DETECTED!")
                print("   This suggests the insert_recall_message RPC function is not deployed or not working.")
                print("   Please run the SQL from supabase/recall.sql in your Supabase SQL editor.")
                print("   Specifically, ensure the insert_recall_message function (lines 126-207) is created.")
            }
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
    
    // MARK: - Reprompt
    
    func reprompt(messageId: UUID, text: String) async {
        guard let threadId = currentThreadId else { return }
        
        do {
            // Insert user reprompt message
            let repromptMessageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .text,
                text: text
            )
            
            await loadMessages()
            
            // Insert status message
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Refining search..."
            )
            
            await loadMessages()
            orbState = .thinking
            
            // Resolve with enhanced context (edge function now inserts all candidates directly)
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: repromptMessageId,
                inputType: .text,
                text: text
            )
            
            // Reload messages to get all candidates inserted by edge function
            await loadMessages()
            
            if let confidence = response.assistantMessage?.confidence {
                orbState = .done(confidence: confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                    }
                }
            } else {
                orbState = .error
            }
            
        } catch {
            errorMessage = "Failed to refine search: \(error.localizedDescription)"
            orbState = .error
            print("❌ Failed to reprompt: \(error)")
        }
    }
    
    // MARK: - Confirm Candidate
    
    func dismissCandidate(messageId: UUID) {
        // Remove the rejected candidate message from the messages array
        messages.removeAll { $0.id == messageId }
        
        rejectionCount += 1
        
        if rejectionCount >= 2 {
            // After 2 rejections, prompt to ask GreenRoom
            showGreenRoomPrompt = true
            greenRoomPromptText = lastUserQuery ?? "Help me find this song"
        } else if rejectionCount == 1 {
            // After first rejection, ask intelligent clarifying questions
            Task {
                await askClarifyingQuestions()
            }
        }
    }
    
    private func askClarifyingQuestions() async {
        guard let threadId = currentThreadId else { return }
        
        orbState = .thinking
        conversationMode = .processing
        
        do {
            // Get context from the conversation
            let rejectedCandidates = messages.filter { $0.messageType == .candidate }
            let lastCandidate = rejectedCandidates.last
            
            // Build a contextual clarifying question based on what we know
            var clarifyingQuestion = ""
            
            if let candidate = lastCandidate?.candidate {
                // We know what was rejected, ask about what they're actually looking for
                let artistName = candidate.artist
                let songTitle = candidate.title
                clarifyingQuestion = "Hmm, that wasn't quite what you had in mind, was it? No worries! Let's find something that hits just right. Can you tell me more about what you're actually looking for? Like, what kind of vibe are you going for - something upbeat to get you moving, something mellow to relax to, or maybe something in between?"
            } else if let lastQuery = lastUserQuery {
                // Ask about specific aspects based on the query
                let queryLower = lastQuery.lowercased()
                if queryLower.contains("mood") || queryLower.contains("feeling") || queryLower.contains("suggest") {
                    clarifyingQuestion = "I'd love to help you find the perfect song! Tell me, what's your vibe right now? Are you feeling happy and energetic, maybe a bit nostalgic, or are you looking for something to just chill and relax to?"
                } else if queryLower.contains("party") || queryLower.contains("dance") || queryLower.contains("upbeat") {
                    clarifyingQuestion = "Got it, you want something with energy! Are you thinking more like a high-energy banger to get everyone moving, or something with a good beat but maybe a bit more laid back?"
                } else if queryLower.contains("chill") || queryLower.contains("relax") || queryLower.contains("calm") {
                    clarifyingQuestion = "Perfect, you're looking for something chill! Are you thinking more like a smooth, mellow vibe, or maybe something acoustic and peaceful?"
                } else {
                    clarifyingQuestion = "Let me help you find something that really fits! Can you tell me a bit more about what you're in the mood for? Like, what kind of energy are you feeling - something to pump you up, something to chill to, or maybe something that matches a specific feeling you have right now?"
                }
            } else {
                clarifyingQuestion = "I want to make sure I find exactly what you're looking for! Can you tell me a bit more about the vibe you're going for? What kind of mood or feeling are you trying to capture right now?"
            }
            
            // Insert the clarifying question as a follow-up message
            let questionMessageId = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .follow_up,
                text: clarifyingQuestion
            )
            
            await loadMessages()
            
            // Set conversation mode to wait for refinement
            shouldWaitForRefinement = true
            pendingFollowUpQuestion = clarifyingQuestion
            conversationMode = .waitingForRefinement
            
            // Store the clarifying question is already stored as a follow_up message above
            // Speak the clarifying question
            voiceResponseService.speak(clarifyingQuestion) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.conversationMode = .waitingForRefinement
                    self.orbState = .idle
                }
            }
            
            orbState = .idle
        } catch {
            errorMessage = "Failed to ask clarifying question: \(error.localizedDescription)"
            orbState = .error
            conversationMode = .idle
            print("❌ Failed to ask clarifying question: \(error)")
        }
    }
    
    private func retrySearch() async {
        guard let threadId = currentThreadId,
              let messageId = lastUserMessageId else { return }
        
        // Clear current candidate messages
        messages.removeAll { $0.messageType == .candidate }
        
        orbState = .thinking
        
        do {
            // Insert status message
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching again..."
            )
            await loadMessages()
            
            // Get the original user message to retry
            let userMessage = messages.first { $0.id == messageId }
            let inputType: RecallInputType = userMessage?.messageType == .voice ? .voice : .text
            let text = userMessage?.text
            let mediaPath = userMessage?.mediaPath
            
            // Resolve again
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: inputType,
                text: text,
                mediaPath: mediaPath
            )
            
            await loadMessages()
            
            if let topCandidate = response.candidates?.first {
                orbState = .done(confidence: topCandidate.confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                    }
                }
            } else {
                orbState = .error
            }
        } catch {
            errorMessage = "Failed to retry search: \(error.localizedDescription)"
            orbState = .error
            print("❌ Failed to retry search: \(error)")
        }
    }
    
    func createGreenRoomPost() async {
        guard let threadId = currentThreadId else { return }
        
        do {
            let feedService = SupabaseFeedService.shared
            let postText = "🎵 Help me find this song!\n\n\"\(greenRoomPromptText)\"\n\n[Recall: Need help identifying this song from memory]"
            
            let post = try await feedService.createPost(
                text: postText,
                imageURLs: [],
                videoURL: nil,
                audioURL: nil,
                leaderboardEntry: nil,
                spotifyLink: nil,
                poll: nil,
                backgroundMusic: nil,
                mentionedUserIds: []
            )
            
            // Clear messages and show orb
            messages = []
            rejectionCount = 0
            showGreenRoomPrompt = false
            orbState = .idle
            
            // Create new thread
            currentThreadId = try await service.createThreadIfNeeded()
            
            // Navigate to GreenRoom (optional)
            NotificationCenter.default.post(
                name: .navigateToFeed,
                object: nil
            )
            
        } catch {
            errorMessage = "Failed to create GreenRoom post: \(error.localizedDescription)"
            print("❌ Failed to create GreenRoom post: \(error)")
        }
    }
    
    func confirmCandidate(messageId: UUID, title: String, artist: String) async {
        guard let threadId = currentThreadId else { return }
        
        do {
            // Get confidence from the message
            let message = messages.first { $0.id == messageId }
            let confidence = message?.confidence
            
            // Add entire thread to stash (thread_id links to all messages in the thread)
            try await service.addToStash(
                threadId: threadId,
                songTitle: title,
                songArtist: artist,
                confidence: confidence
            )
            
            // Clear messages to show orb immediately
            await MainActor.run {
                messages = []
                orbState = .idle
            }
            
            // Create a NEW thread for next search (don't reuse existing)
            currentThreadId = try await service.createNewThread()
            
        } catch {
            errorMessage = "Failed to confirm: \(error.localizedDescription)"
            print("❌ Failed to confirm candidate: \(error)")
        }
    }
    
    // MARK: - Open Thread
    
    func openThread(threadId: UUID) async {
        currentThreadId = threadId
        await loadMessages()
    }
    
    // MARK: - Confirm Answer Response
    
    func confirmAnswerResponse(messageId: UUID) async {
        // If there's a pending transcript, confirm it first
        if pendingTranscript != nil {
            await confirmPendingTranscript()
            return
        }
        
        // Provide haptic feedback that the answer was helpful
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
        
        // Get the message that was confirmed
        let confirmedMessage = messages.first { $0.id == messageId }
        let messageText = confirmedMessage?.text ?? "response"
        
        // Mark as confirmed
        confirmedMessageIds.insert(messageId)
        
        // Speak confirmation with context
        let confirmationText = "Great! I'm glad that was helpful. Is there anything else you'd like to know?"
        
        // Set pending transcript for confirmation (not saved yet)
        setPendingTranscript(confirmationText, messageType: .text)
        
        // Speak the confirmation
        voiceResponseService.speak(confirmationText) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.orbState = .idle
                self.conversationMode = .idle
            }
        }
        
        print("✅ User confirmed answer response: \(messageText.prefix(50))")
    }
    
    func declineAnswerResponse(messageId: UUID) async {
        // If there's a pending transcript, decline it first
        if pendingTranscript != nil {
            await declinePendingTranscript()
            return
        }
        
        // Remove or mark the declined message
        let declinedMessage = messages.first { $0.id == messageId }
        
        // Remove from confirmed messages
        confirmedMessageIds.remove(messageId)
        
        // Ask clarifying questions to better understand what the user needs
        await askClarifyingQuestions()
        
        print("❌ User declined answer response, asking clarifying questions")
    }
}

