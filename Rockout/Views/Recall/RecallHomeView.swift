import SwiftUI

struct RecallHomeView: View {
    @StateObject private var viewModel = RecallViewModel()
    @State private var showStashed = false
    @State private var showStashedThreads = false
    @State private var showSettings = false
    @FocusState private var isTextFieldFocused: Bool
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isLongPressing: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView
                mainContent
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1.5)
                    .sequenced(before: DragGesture(minimumDistance: 10))
                    .updating($isLongPressing) { value, state, _ in
                        switch value {
                        case .first(true):
                            // Long press started - notify state machine
                            // Only proceed if NOT scrolling and gate conditions are met
                            if !state {
                                // Check if user is scrolling or in cooldown - if so, ignore the gesture
                                if viewModel.stateMachine.isScrolling || viewModel.stateMachine.scrollCooldownActive {
                                    return
                                }
                                
                                state = true
                                // Check gate conditions via state machine
                                if viewModel.stateMachine.currentState == .listening || viewModel.stateMachine.currentState == .processing {
                                    return
                                }
                                // Notify state machine first
                                viewModel.stateMachine.handleEvent(.longPressBegan)
                                // Only proceed if state machine allows (checks scrolling and cooldown again)
                                guard viewModel.stateMachine.currentState == .armed || viewModel.stateMachine.currentState == .listening else {
                                    return
                                }
                                Task {
                                    await viewModel.orbLongPressed()
                                }
                            }
                        case .second(true, let dragValue):
                            // Still pressing and dragging - check if drag distance is too large
                            // If user drags too far, cancel the gesture
                            if let drag = dragValue, abs(drag.translation.width) > 50 || abs(drag.translation.height) > 50 {
                                // User dragged too far - cancel
                                state = false
                                viewModel.stateMachine.handleEvent(.longPressEnded)
                                Task {
                                    await viewModel.orbLongPressEnded()
                                }
                                return
                            }
                            // Still pressing within acceptable range - keep recording
                            state = true
                            break
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        // Contact lost - stop recording immediately
                        viewModel.stateMachine.handleEvent(.longPressEnded)
                        Task {
                            await viewModel.orbLongPressEnded()
                        }
                    }
            )
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
                        // New Thread option - only show when there are messages
                        if !viewModel.messages.isEmpty {
                            Button {
                                Task {
                                    // Don't show welcome when user manually creates new thread
                                    await viewModel.startNewSession(showWelcome: false)
                                }
                            } label: {
                                Label("New Thread", systemImage: "plus.circle.fill")
                            }
                            .accessibilityLabel("New Thread")
                            .accessibilityHint("Double tap to start a new conversation thread")
                            
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
            .onChange(of: scenePhase) { oldPhase, newPhase in
                // Stop speaking when app goes to background or becomes inactive
                if newPhase == .background || newPhase == .inactive {
                    VoiceResponseService.shared.stopSpeaking()
                    print("🔇 [LIFECYCLE] Stopped speaking because app went to \(newPhase == .background ? "background" : "inactive")")
                }
                
                // When app comes to foreground after being in background/inactive, reset welcome flag
                // so welcome shows again on next app open (app restart)
                if (oldPhase == .background || oldPhase == .inactive) && newPhase == .active {
                    // Reset welcome flag so it shows on next Recall open after app restart
                    viewModel.resetWelcomeFlag()
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
        }
    }
    
    private var orbView: some View {
        RecallOrbView(
            state: viewModel.orbState,
            conversationMode: viewModel.conversationMode,
            isSpeaking: viewModel.isSpeaking,
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
        .onTapGesture {
            // Tap to stop recording if currently recording
            // Check if recording by checking the state
            if case .listening = viewModel.orbState {
                Task {
                    await viewModel.orbTapped()
                }
            }
        }
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
                    .opacity(1.0) // Ensure messages are always fully visible
                
                // Live transcript and transcript composer removed (files were deleted in stash revert)
                
                composerBar
            }
        } else {
            VStack {
                Spacer()
                
                // Live transcript and transcript composer removed (files were deleted in stash revert)
                
                composerBar
            }
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
