import SwiftUI

struct RecallMessageBubble: View {
    let message: RecallMessage
    let onConfirm: (() -> Void)?
    let onNotIt: ((UUID) -> Void)?
    let onDecline: ((UUID) -> Void)?
    let onReprompt: ((UUID, String) -> Void)?
    let onAskGreenRoom: (() -> Void)? // CTA for low confidence
    let onRegenerate: ((UUID) -> Void)? // Regenerate answer
    // Use @ObservedObject instead of @StateObject for singleton to ensure updates are observed
    @ObservedObject private var voiceResponseService = VoiceResponseService.shared
    @State private var isPressed = false
    
    init(
        message: RecallMessage,
        onConfirm: (() -> Void)? = nil,
        onNotIt: ((UUID) -> Void)? = nil,
        onDecline: ((UUID) -> Void)? = nil,
        onReprompt: ((UUID, String) -> Void)? = nil,
        onAskGreenRoom: (() -> Void)? = nil,
        onRegenerate: ((UUID) -> Void)? = nil
    ) {
        self.message = message
        self.onConfirm = onConfirm
        self.onNotIt = onNotIt
        self.onDecline = onDecline
        self.onReprompt = onReprompt
        self.onAskGreenRoom = onAskGreenRoom
        self.onRegenerate = onRegenerate
    }
    
    var body: some View {
        let _ = print("📱 [TRANSCRIPT] RecallMessageBubble body rendering:")
        let _ = print("   - Message ID: \(message.id)")
        let _ = print("   - Message type: \(message.messageType)")
        let _ = print("   - Message role: \(message.role)")
        let _ = print("   - Has text: \(message.text != nil)")
        
        return VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            HStack {
                if message.role == .user {
                    Spacer()
                }
                
                Group {
                    switch message.messageType {
                    case .text, .voice:
                        if message.role == .assistant && (message.messageType == .text || message.messageType == .answer) {
                            answerMessageView
                        } else {
                            userMessageView
                        }
                    case .answer:
                        // Answer messages always show the answer view
                        answerMessageView
                    case .image:
                        imageMessageView
                    case .status:
                        statusMessageView
                    case .follow_up:
                        followUpMessageView
                    case .candidate:
                        if let candidate = message.candidate {
                            RecallCandidateCard(
                                candidate: candidate,
                                sources: message.sourcesJson,
                                songUrl: message.songUrl,
                                onOpenSong: {
                                    if let urlString = message.songUrl,
                                       let url = URL(string: urlString) {
                                        UIApplication.shared.open(url)
                                    }
                                },
                                onConfirm: {
                                    onConfirm?()
                                },
                                onNotIt: {
                                    onNotIt?(message.id)
                                },
                                onReprompt: { text in
                                    onReprompt?(message.id, text)
                                },
                                onAskGreenRoom: candidate.confidence < 0.65 ? onAskGreenRoom : nil
                            )
                        } else {
                            Text(message.text ?? "Unknown message")
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(maxWidth: message.role == .assistant && message.messageType == .candidate ? UIScreen.main.bounds.width * 0.95 : UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)
                
                if message.role == .assistant {
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            // Transcript display below each assistant response
            if message.role == .assistant {
                transcriptView
                    .padding(.horizontal, 16)
            }
        }
    }
    
    private var userMessageView: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.messageType == .voice {
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.subheadline)
                            Text("Voice note")
                                .font(.subheadline)
                        }
                        
                        // Show transcription if available
                        if let transcription = message.text, !transcription.isEmpty {
                            Text("\"\(transcription)\"")
                                .font(.body)
                                .italic()
                                .padding(.top, 4)
                                .accessibilityLabel("Transcription: \(transcription)")
                        }
                    }
                } else {
                    Text(message.text ?? "")
                        .font(.body)
                }
                
                HStack(spacing: 4) {
                    // Status indicator
                    if let status = message.status {
                        switch status {
                        case .sending:
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Sending...")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.7))
                        case .failed:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text("Failed")
                                .font(.caption2)
                                .foregroundColor(.red)
                        case .sent:
                            Text(message.createdAt.timeAgoDisplay())
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    } else {
                        Text(message.createdAt.timeAgoDisplay())
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(message.role == .user ? Color(hex: "#1ED760") : Color.white.opacity(0.1))
            )
            .foregroundColor(message.role == .user ? .white : .white)
            
            // Refine button - only show for user messages
            if message.role == .user {
                Button {
                    // Show reprompt sheet to refine this message
                    // We'll handle this through a callback to the parent view
                    if let onReprompt = onReprompt {
                        onReprompt(message.id, message.text ?? "")
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.2))
                        )
                }
                .accessibilityLabel("Refine search")
                .accessibilityHint("Double tap to refine this search query")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "Your message" : "Assistant message")
        .accessibilityValue(message.text ?? "")
    }
    
    private var imageMessageView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let mediaPath = message.mediaPath {
                AsyncImage(url: URL(string: mediaPath)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 200)
                        .overlay {
                            ProgressView()
                        }
                }
                .frame(maxHeight: 200)
                .cornerRadius(12)
            }
            
            Text(message.createdAt.timeAgoDisplay())
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#1ED760"))
        )
    }
    
    private var statusMessageView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(message.text ?? "Searching...")
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
        .foregroundColor(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(message.text ?? "")")
    }
    
    private var followUpMessageView: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "#1ED760"))
                
                Text(message.text ?? "")
                    .font(.body)
                    .foregroundColor(.white)
                
                Spacer()
                
                // TTS playback control
                Button(action: {
                    if voiceResponseService.isSpeaking {
                        voiceResponseService.stopSpeaking()
                    } else if let text = message.text {
                        voiceResponseService.speak(text)
                    }
                }) {
                    Image(systemName: voiceResponseService.isSpeaking ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "#1ED760"))
                }
            }
            
            // Transcript display for voice responses - ALWAYS show what was spoken
            if let transcript = message.text, !transcript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Spoken:")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                            .textCase(.uppercase)
                    }
                    Text("\"\(transcript)\"")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                .accessibilityLabel("Transcript: \(transcript)")
            }
            
            Text("Tap to respond with your voice")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .italic()
                .padding(.top, 4)
            
            // No confirm/decline buttons for clarifying questions
        }
        
        let backgroundOpacity = isPressed ? 0.25 : 0.15
        let accessibilityLabel = "Follow-up question: \(message.text ?? "")"
        
        return content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(backgroundOpacity))
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Long press to respond with your voice")
            .accessibilityAddTraits(.isButton)
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                isPressed = pressing
            }, perform: {})
            .onAppear {
                // Auto-play follow-up questions
                if let text = message.text, !text.isEmpty {
                    voiceResponseService.speak(text)
                }
            }
    }
    
    // Helper to determine if confirm/decline buttons should be shown
    private var shouldShowConfirmDeclineButtons: Bool {
        // Don't show for welcome message (exact match to avoid false positives)
        if let text = message.text, text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Hi! I'm Recall") && text.count < 200 {
            return false
        }
        // Don't show for clarifying questions (follow_up type)
        if message.messageType == .follow_up {
            return false
        }
        // Don't show for status messages
        if message.messageType == .status {
            return false
        }
        // ALWAYS show for answer messages (so users can confirm information)
        if message.messageType == .answer {
            return true
        }
        // Show for conversational outputs (text type) that are assistant responses
        if message.messageType == .text && message.role == .assistant {
            // Check if it's a result message (starts with "I found")
            if let text = message.text, text.hasPrefix("I found") {
                return true // Show buttons for results
            }
            // Show for all other conversational outputs (answers to questions)
            return true
        }
        return false
    }
    
    private var answerMessageView: some View {
        let _ = print("🎨 [TRANSCRIPT] answerMessageView rendering:")
        let _ = print("   - Message ID: \(message.id)")
        let _ = print("   - Message type: \(message.messageType)")
        let _ = print("   - Message role: \(message.role)")
        let _ = print("   - Has text: \(message.text != nil)")
        let _ = print("   - Text content: \(message.text?.prefix(100) ?? "nil")")
        let _ = print("   - Text isEmpty: \(message.text?.isEmpty ?? true)")
        
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: "#1ED760"))
                
                Text(message.text ?? "")
                    .font(.body)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                // TTS playback control
                Button(action: {
                    if voiceResponseService.isSpeaking {
                        voiceResponseService.stopSpeaking()
                    } else if let text = message.text {
                        voiceResponseService.speak(text)
                    }
                }) {
                    Image(systemName: voiceResponseService.isSpeaking ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "#1ED760"))
                }
                .accessibilityLabel(voiceResponseService.isSpeaking ? "Pause playback" : "Play audio")
                .accessibilityHint("Double tap to \(voiceResponseService.isSpeaking ? "pause" : "play") the answer")
            }
            
            if !message.sourcesJson.isEmpty {
                Text("\(message.sourcesJson.count) source\(message.sourcesJson.count > 1 ? "s" : "")")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 4)
            }
            
            // Regenerate button for assistant messages
            if message.role == .assistant, let onRegenerate = onRegenerate {
                Button {
                    onRegenerate(message.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14))
                        Text("Regenerate")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .accessibilityLabel("Regenerate answer")
                .accessibilityHint("Double tap to regenerate this response")
                .padding(.top, 4)
            }
            
            // Confirm and Decline buttons - only for conversational outputs and results, not welcome or clarifying questions
            if shouldShowConfirmDeclineButtons {
                HStack(spacing: 12) {
                    Button {
                        onConfirm?()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Confirm")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#1ED760"))
                        )
                    }
                    .accessibilityLabel("Confirm response")
                    .accessibilityHint("Double tap to confirm this response")
                    
                    Button {
                        onDecline?(message.id)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                            Text("Not Quite")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.7))
                        )
                    }
                    .accessibilityLabel("Decline response")
                    .accessibilityHint("Double tap to decline and ask clarifying questions")
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.15))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Answer: \(message.text ?? "")")
        .accessibilityValue(message.sourcesJson.isEmpty ? "" : "\(message.sourcesJson.count) source\(message.sourcesJson.count > 1 ? "s" : "")")
    }
    
    // Transcript view - displayed below each assistant response
    // Only shows pending transcript (not saved) or confirmed saved messages
    @ViewBuilder
    private var transcriptView: some View {
        // Check if this is a confirmed saved message - show its transcript
        if let transcript = message.text, !transcript.isEmpty, message.role == .assistant {
            // Only show transcript for confirmed messages (saved in database)
            // Don't show for pending transcripts (those are shown separately)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "#1ED760"))
                    Text("Spoken:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .textCase(.uppercase)
                }
                
                // Show full transcript for confirmed messages
                Text("\"\(transcript)\"")
                    .font(.body)
                    .foregroundColor(.white)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#1ED760").opacity(0.3), lineWidth: 1)
                    )
            )
            .accessibilityLabel("Transcript: \(transcript)")
        }
    }
    
    // Pending transcript view - shown separately for current speaking message
    @ViewBuilder
    static func pendingTranscriptView(
        pendingTranscript: (text: String, messageType: RecallMessageType, id: UUID)?,
        voiceResponseService: VoiceResponseService,
        onConfirm: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) -> some View {
        if let pending = pendingTranscript {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "#1ED760"))
                    Text(voiceResponseService.isSpeaking ? "Speaking:" : "Preview:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .textCase(.uppercase)
                }
                
                // Show live transcript if speaking, or full preview if done
                if voiceResponseService.isSpeaking {
                    if !voiceResponseService.currentSpokenText.isEmpty {
                        // Live transcript - updates as words are spoken in real-time
                        HStack(alignment: .top, spacing: 4) {
                            Text("\"\(voiceResponseService.currentSpokenText)\"")
                                .font(.body)
                                .foregroundColor(.white)
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(4)
                            
                            // Cursor indicator to show live typing effect
                            Text("|")
                                .font(.body)
                                .foregroundColor(Color(hex: "#1ED760"))
                                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: voiceResponseService.isSpeaking)
                        }
                        .animation(.easeInOut(duration: 0.1), value: voiceResponseService.currentSpokenText)
                    } else {
                        // Speaking but currentSpokenText not yet available - show full transcript with "Speaking" indicator
                        HStack(alignment: .top, spacing: 4) {
                            Text("\"\(pending.text)\"")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.7))
                                .italic()
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(4)
                            
                            // Cursor indicator to show live typing effect
                            Text("|")
                                .font(.body)
                                .foregroundColor(Color(hex: "#1ED760"))
                                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: voiceResponseService.isSpeaking)
                        }
                    }
                } else {
                    // Full preview when not speaking - ready for confirmation
                    Text("\"\(pending.text)\"")
                        .font(.body)
                        .foregroundColor(.white)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(4)
                }
                
                // Confirm/Decline buttons - only show after speaking is done
                if !voiceResponseService.isSpeaking {
                    HStack(spacing: 12) {
                        Button {
                            onConfirm()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                Text("Confirm")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: "#1ED760"))
                            )
                        }
                        .accessibilityLabel("Confirm transcript")
                        .accessibilityHint("Double tap to confirm and save this response")
                        
                        Button {
                            onDecline()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                Text("Decline")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.7))
                            )
                        }
                        .accessibilityLabel("Decline transcript")
                        .accessibilityHint("Double tap to decline and request a new answer")
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#1ED760").opacity(0.3), lineWidth: 1)
                    )
            )
            .accessibilityLabel("Pending transcript: \(pending.text)")
        }
    }
}

