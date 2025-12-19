import SwiftUI

struct RecallHomeView: View {
    @StateObject private var viewModel = RecallViewModel()
    @State private var showStashed = false
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
                LongPressGesture(minimumDuration: 3.0)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .updating($isLongPressing) { value, state, _ in
                        switch value {
                        case .first(true):
                            // Long press started - start recording
                            if !state {
                                state = true
                                if case .listening = viewModel.orbState {
                                    return
                                }
                                guard !viewModel.isProcessing else { return }
                                Task {
                                    await viewModel.orbLongPressed()
                                }
                            }
                        case .second(true, _):
                            // Still pressing - keep recording
                            state = true
                            break
                        default:
                            break
                        }
                    }
                    .onEnded { _ in
                        // Long press ended - stop recording
                        // @GestureState automatically resets to false
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
                    .accessibilityHint("Double tap to open menu with options for new thread and stashed songs")
                }
            }
            .sheet(isPresented: $showStashed) {
                RecallStashedView(viewModel: viewModel)
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
                // When app comes to foreground after being in background, reset welcome flag
                // so welcome shows again on next app open
                if oldPhase == .background && newPhase == .active {
                    // Reset welcome flag so it shows on next Recall open
                    // This will be handled by checkAndShowWelcomeOnAppOpen
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
                composerBar
            }
        } else {
            VStack {
                Spacer()
                composerBar
            }
        }
    }
    
    // Filter messages to hide status messages when there's an answer message after them
    private var filteredMessages: [RecallMessage] {
        var filtered: [RecallMessage] = []
        
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
                filtered.append(message)
            }
        }
        
        print("📋 [TRANSCRIPT] Filtered messages: \(filtered.count) of \(viewModel.messages.count)")
        for (idx, msg) in filtered.enumerated() {
            print("   [\(idx)] type=\(msg.messageType), role=\(msg.role), text=\(msg.text?.prefix(30) ?? "nil")")
        }
        
        return filtered
    }
    
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
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
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = filteredMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.conversationMode) { oldMode, newMode in
                // Scroll to last message when Recall starts speaking
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
                            artist: candidate.artist
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
