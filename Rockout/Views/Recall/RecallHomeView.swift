import SwiftUI

struct RecallHomeView: View {
    @StateObject private var viewModel = RecallViewModel()
    @State private var showStashed = false
    @State private var showStashedThreads = false
    @State private var showSettings = false
    @FocusState private var isTextFieldFocused: Bool
    @State private var dragOffset: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView
                mainContent
            }
            // Voice Mode: tap-to-start/tap-to-stop handled by RecallOrbView (no long-press)
            .navigationTitle("Recall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isProcessing || viewModel.canTerminateSession {
                        Button(action: {
                            if viewModel.isProcessing {
                                viewModel.cancelProcessing()
                            } else {
                                viewModel.terminateSession()
                            }
                        }) {
                            Image(systemName: viewModel.isProcessing ? "stop.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 20))
                        }
                        .accessibilityLabel(viewModel.isProcessing ? "Stop processing" : "Close session")
                        .accessibilityHint("Double tap to \(viewModel.isProcessing ? "stop processing" : "close the current session")")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if !viewModel.messages.isEmpty {
                            Button {
                                Task {
                                    await viewModel.startNewSession(showWelcome: false)
                                }
                            } label: {
                                Label("New Thread", systemImage: "plus.circle.fill")
                            }
                            .accessibilityLabel("New Thread")
                            .accessibilityHint("Double tap to start a new conversation thread")

                            Button {
                                viewModel.terminateSession()
                            } label: {
                                Label("End Session", systemImage: "xmark.circle.fill")
                            }
                            .accessibilityLabel("End Session")
                            .accessibilityHint("Double tap to end the current conversation and return to idle")

                            Divider()
                        }
                        
                        // View Stashed Threads
                        Button {
                            showStashedThreads = true
                        } label: {
                            Label("Stashed Threads", systemImage: "bubble.left.and.bubble.right.fill")
                        }
                        .accessibilityLabel("Stashed Threads")
                        .accessibilityHint("Double tap to view your conversation threads")
                        
                        Divider()
                        
                        // Settings
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityHint("Double tap to open Recall settings")
                        
                        Divider()
                        
                        // View Stashed Songs
                        Button {
                            showStashed = true
                        } label: {
                            Label("Stashed Songs", systemImage: "bookmark.fill")
                        }
                        .accessibilityLabel("Stashed Songs")
                        .accessibilityHint("Double tap to view your saved songs")
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .foregroundColor(Color(hex: "#1ED760"))
                            .font(.system(size: 22))
                    }
                    .accessibilityLabel("Menu")
                    .accessibilityHint("Double tap to open menu with options for new thread, stashed threads, and stashed songs")
                }
            }
            .sheet(isPresented: $showStashed) {
                RecallStashedView(viewModel: viewModel)
            }
            .sheet(isPresented: $showStashedThreads) {
                RecallStashedThreadsView(recallViewModel: viewModel)
            }
            .sheet(isPresented: $showSettings) {
                RecallSettingsView()
            }
            .sheet(isPresented: $viewModel.showGreenRoomPrompt) {
                GreenRoomPromptSheet(
                    promptText: viewModel.greenRoomPromptText,
                    onPost: {
                        Task {
                            await viewModel.createGreenRoomPost()
                        }
                    },
                    onCancel: {
                        viewModel.showGreenRoomPrompt = false
                        viewModel.rejectionCount = 0
                    }
                )
            }
            .sheet(isPresented: $viewModel.showRepromptSheet) {
                RecallRepromptSheet(
                    originalQuery: viewModel.lastUserQuery ?? "Previous search",
                    onReprompt: { text in
                        viewModel.showRepromptSheet = false
                        if let lastMessageId = viewModel.messages.last(where: { $0.role == .user })?.id {
                            Task {
                                await viewModel.reprompt(messageId: lastMessageId, text: text)
                            }
                        }
                    }
                )
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .onAppear {
                // Check and show welcome only on first app open or first time use
                Task {
                    await viewModel.checkAndShowWelcomeOnAppOpen()
                }
            }
            .onDisappear {
                // Stop speaking when user leaves Recall tab (e.g. switches to another tab)
                VoiceResponseService.shared.stopSpeaking()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Stop speaking when app goes to background or becomes inactive
                if newPhase == .background || newPhase == .inactive {
                    VoiceResponseService.shared.stopSpeaking()
                    print("🔇 [LIFECYCLE] Stopped speaking because app went to \(newPhase == .background ? "background" : "inactive")")
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var backgroundView: some View {
        AnimatedGradientBackground()
            .ignoresSafeArea()
            .onTapGesture {
                isTextFieldFocused = false
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 50 && isTextFieldFocused {
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            isTextFieldFocused = false
                        }
                        dragOffset = 0
                    }
            )
    }
    
    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            orbView
            conversationModeIndicator
            messagesOverlay
            voiceModeControls
        }
    }

    /// ChatGPT-style: Mute (bottom-left), Exit (bottom-right) when voice session is active.
    @ViewBuilder
    private var voiceModeControls: some View {
        if viewModel.isVoiceModeActive {
            HStack {
                Button {
                    if viewModel.voiceOrchestrator.isMuted {
                        viewModel.voiceModeUnmute()
                    } else {
                        viewModel.voiceModeMute()
                    }
                } label: {
                    Image(systemName: viewModel.voiceOrchestrator.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(viewModel.voiceOrchestrator.isMuted ? "Unmute microphone" : "Mute microphone")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Double tap to \(viewModel.voiceOrchestrator.isMuted ? "resume listening" : "pause listening")")

                Spacer()

                Button {
                    viewModel.voiceModeExit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("End voice session")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Double tap to end the voice conversation and return to idle")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 140)
        }
    }
    
    private var orbView: some View {
        RecallOrbView(
            state: viewModel.orbState,
            conversationMode: viewModel.conversationMode,
            isSpeaking: viewModel.isSpeaking,
            useTapMode: true,
            onTap: {
                Task {
                    await viewModel.orbTappedForVoiceMode()
                }
            },
            onLongPress: {
                Task {
                    await viewModel.orbLongPressed()
                }
            },
            onLongPressEnd: {
                Task {
                    await viewModel.orbLongPressEnded()
                }
            }
        )
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var conversationModeIndicator: some View {
        if viewModel.conversationMode == .waitingForRefinement {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(hex: "#1ED760"))
                        Text("Ready for your response")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.7))
                    )
                    .padding(.bottom, 100)
                    Spacer()
                }
            }
        } else if viewModel.conversationMode == .speaking || viewModel.isSpeaking {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(Color(hex: "#1ED760"))
                        Text("Recall is speaking...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.7))
                    )
                    .padding(.bottom, 100)
                    Spacer()
                }
            }
            .allowsHitTesting(false) // Don't block interaction with messages
        }
    }
    
    @ViewBuilder
    private var messagesOverlay: some View {
        if !viewModel.messages.isEmpty {
            VStack(spacing: 0) {
                messagesScrollView
                    .opacity(1.0)
                liveTranscriptView
                composerBar
                    .padding(.bottom, 50)
            }
        } else {
            VStack {
                Spacer()
                liveTranscriptView
                composerBar
                    .padding(.bottom, 50)
            }
        }
    }

    @ViewBuilder
    private var liveTranscriptView: some View {
        if viewModel.isVoiceModeActive,
           case .listening = viewModel.orbState,
           viewModel.voiceOrchestrator.currentState == .listening || viewModel.voiceOrchestrator.currentState == .capturingUtterance {
            RecallLiveTranscriptView(
                transcript: viewModel.liveTranscript,
                isRecording: true
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }
    
    // Filter messages to hide status messages when there's an answer message after them
    private var filteredMessages: [RecallMessage] {
        var filtered: [RecallMessage] = []
        
        // Log all messages for debugging
        print("🔍 [TRANSCRIPT] Filtering messages - total: \(viewModel.messages.count)")
        
        for (index, message) in viewModel.messages.enumerated() {
            if message.messageType == .status {
                // Check if there's an answer, candidate, or assistant text message after this status
                let remainingMessages = Array(viewModel.messages[index...].dropFirst())
                let hasAnswerAfter = remainingMessages.contains { msg in
                    // Answer message (conversational responses, music info, etc.)
                    msg.messageType == .answer ||
                    // Candidate message (song identification results)
                    msg.messageType == .candidate ||
                    // Assistant text message (could be answer from edge function or conversational response)
                    (msg.messageType == .text && msg.role == .assistant && msg.text != nil && !msg.text!.isEmpty) ||
                    // Follow-up question (also means answer was processed)
                    msg.messageType == .follow_up
                }
                
                // Only hide status if there's an answer after it
                if !hasAnswerAfter {
                    filtered.append(message)
                    print("✅ [TRANSCRIPT] Showing status message (no answer after it)")
                } else {
                    print("🚫 [TRANSCRIPT] Hiding status message because answer exists after it at index \(index)")
                }
            } else {
                // Include all non-status messages
                filtered.append(message)
                print("✅ [TRANSCRIPT] Including message [\(index)]: type=\(message.messageType), role=\(message.role), hasText=\(message.text != nil && !message.text!.isEmpty)")
            }
        }
        
        print("📋 [TRANSCRIPT] Filtered messages: \(filtered.count) of \(viewModel.messages.count)")
        for (idx, msg) in filtered.enumerated() {
            print("   [\(idx)] id=\(msg.id), type=\(msg.messageType), role=\(msg.role), text=\(msg.text?.prefix(30) ?? "nil")")
        }
        
        return filtered
    }
    
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    // Loading indicator for older messages at top
                    if viewModel.isLoadingOlderMessages {
                        ProgressView()
                            .tint(.white)
                            .padding()
                    }
                    
                    // Scroll velocity reader for state machine (invisible, tracks scroll)
                    ScrollVelocityReader(
                        scrollVelocity: .constant(0),
                        isScrolling: Binding(
                            get: { viewModel.stateMachine.isScrolling },
                            set: { newValue in
                                if newValue {
                                    viewModel.stateMachine.handleEvent(.scrollStarted)
                                } else {
                                    viewModel.stateMachine.handleEvent(.scrollEnded)
                                }
                            }
                        )
                    )
                    .frame(height: 0)
                    .opacity(0)
                    .onAppear {
                        // Load older messages when scrolling to top
                        if viewModel.hasMoreMessages && !viewModel.isLoadingOlderMessages {
                            Task {
                                await viewModel.loadOlderMessages()
                            }
                        }
                    }
                    
                    // Filter out status messages that have been superseded by answer messages
                    ForEach(filteredMessages) { message in
                        messageBubble(for: message)
                            .id(message.id)
                    }
                    
                    // Pending transcript view - shown separately below all messages
                    if let pending = viewModel.pendingTranscript {
                        RecallMessageBubble.pendingTranscriptView(
                            pendingTranscript: pending,
                            voiceResponseService: VoiceResponseService.shared,
                            onConfirm: {
                                Task {
                                    await viewModel.confirmPendingTranscript()
                                }
                            },
                            onDecline: {
                                Task {
                                    await viewModel.declinePendingTranscript()
                                }
                            }
                        )
                        .id("pending-transcript")
                    }
                }
                .padding(.vertical, 16)
                .padding(.bottom, 100)
            }
            .coordinateSpace(name: "scrollView") // Required for ScrollVelocityReader
            .disabled(viewModel.stateMachine.currentState == .listening) // Disable scrolling when listening
            .onChange(of: viewModel.stateMachine.isScrolling) { oldValue, newValue in
                // Update state machine when scroll state changes
                if newValue && !oldValue {
                    viewModel.stateMachine.handleEvent(.scrollStarted)
                } else if !newValue && oldValue {
                    viewModel.stateMachine.handleEvent(.scrollEnded)
                }
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                print("🔄 [TRANSCRIPT] Messages count changed: \(oldCount) -> \(newCount)")
                if let lastMessage = filteredMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.messages) { oldMessages, newMessages in
                print("🔄 [TRANSCRIPT] Messages array changed: \(oldMessages.count) -> \(newMessages.count)")
                // Force UI refresh when messages change
                if let lastMessage = filteredMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.conversationMode) { oldMode, newMode in
                // Scroll to last message when Recall starts speaking
                print("🔄 [TRANSCRIPT] Conversation mode changed: \(oldMode) -> \(newMode)")
                if newMode == .speaking, let lastMessage = filteredMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private func messageBubble(for message: RecallMessage) -> some View {
        RecallMessageBubble(
            message: message,
            onConfirm: {
                if let candidate = message.candidate {
                    Task {
                        await viewModel.confirmCandidate(
                            messageId: message.id,
                            title: candidate.title,
                            artist: candidate.artist,
                            url: message.songUrl
                        )
                    }
                } else if message.role == .assistant && (message.messageType == .text || message.messageType == .answer || message.messageType == .follow_up) {
                    // Confirm assistant answer response or follow-up question
                    Task {
                        await viewModel.confirmAnswerResponse(messageId: message.id)
                    }
                }
            },
            onNotIt: { messageId in
                viewModel.dismissCandidate(messageId: messageId)
            },
            onDecline: { messageId in
                // Decline answer response and ask clarifying questions
                Task {
                    await viewModel.declineAnswerResponse(messageId: messageId)
                }
            },
            onReprompt: { messageId, text in
                // Store the message ID and original query for the reprompt sheet
                viewModel.repromptMessageId = messageId
                viewModel.repromptOriginalQuery = text
                viewModel.showRepromptSheet = true
            },
            onAskGreenRoom: {
                Task {
                    await viewModel.createGreenRoomPost()
                }
            },
            onRegenerate: { messageId in
                Task {
                    await viewModel.regenerateAnswer(messageId: messageId)
                }
            }
        )
    }
    
    
    private var composerBar: some View {
        RecallComposerBar(
            text: $viewModel.composerText,
            isFocused: $isTextFieldFocused,
            onImageSelected: { image in
                Task {
                    await viewModel.pickImage(image)
                }
            },
            onVideoSelected: { videoURL in
                Task {
                    await viewModel.pickVideo(videoURL)
                }
            },
            onSend: {
                Task {
                    await viewModel.sendText()
                    isTextFieldFocused = false
                }
            }
        )
    }
}
