import SwiftUI

struct RecallOrbView: View {
    let state: RecallOrbState
    let conversationMode: ConversationMode?
    let isSpeaking: Bool
    let onLongPress: () -> Void
    let onLongPressEnd: () -> Void
    
    init(
        state: RecallOrbState,
        conversationMode: ConversationMode? = nil,
        isSpeaking: Bool = false,
        onLongPress: @escaping () -> Void,
        onLongPressEnd: @escaping () -> Void
    ) {
        self.state = state
        self.conversationMode = conversationMode
        self.isSpeaking = isSpeaking
        self.onLongPress = onLongPress
        self.onLongPressEnd = onLongPressEnd
    }
    
    @GestureState private var isPressed = false
    @State private var scale: CGFloat = 1.0
    @State private var glowIntensity: Double = 0.0
    @State private var pulseAnimation: Bool = false
    @State private var showRecordingIndicator: Bool = false
    
    private var isRecording: Bool {
        if case .listening = state {
            return true
        }
        return isPressed || glowIntensity > 0
    }
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            
            ZStack {
                // GIF Orb
                if Bundle.main.path(forResource: "recallOrb", ofType: "GIF") != nil {
                    GifImage("recallOrb.GIF")
                        .frame(width: size, height: size)
                        .scaleEffect(scale)
                        .opacity(stateBasedOpacity)
                        .overlay(
                            // Green glow overlay - clipped to orb bounds
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(hex: "#1ED760").opacity(isRecording ? 0.3 * glowIntensity : 0),
                                            Color(hex: "#1ED760").opacity(isRecording ? 0.15 * glowIntensity : 0),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: size * 0.4,
                                        endRadius: size * 0.6
                                    )
                                )
                                .frame(width: size, height: size)
                        )
                        .clipShape(Circle()) // Clip to prevent glow from extending beyond orb
                } else {
                    // Fallback if GIF not found
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.9),
                                    Color(hex: "#1ED760").opacity(0.7),
                                    Color(hex: "#1ED760").opacity(0.3)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size / 2
                            )
                        )
                        .frame(width: size, height: size)
                        .scaleEffect(scale)
                        .overlay(
                            // Green glow overlay - clipped to orb bounds
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(hex: "#1ED760").opacity(isRecording ? 0.3 * glowIntensity : 0),
                                            Color(hex: "#1ED760").opacity(isRecording ? 0.15 * glowIntensity : 0),
                                            Color.clear
                                        ],
                                        center: .center,
                                        startRadius: size * 0.4,
                                        endRadius: size * 0.6
                                    )
                                )
                                .frame(width: size, height: size)
                        )
                        .clipShape(Circle()) // Clip to prevent glow from extending beyond orb
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped() // Additional clipping to ensure nothing extends beyond bounds
            .overlay(
                // Conversation mode indicator - pulsing when waiting for refinement
                Group {
                    if conversationMode == .waitingForRefinement {
                        Circle()
                            .stroke(Color(hex: "#1ED760"), lineWidth: 3)
                            .frame(width: size * 1.2, height: size * 1.2)
                            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            .opacity(pulseAnimation ? 0.3 : 0.6)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                            .onAppear {
                                pulseAnimation = true
                            }
                    } else if conversationMode == .speaking || isSpeaking || state == .responding {
                        Circle()
                            .stroke(Color(hex: "#1ED760").opacity(0.5), lineWidth: 2)
                            .frame(width: size * 1.1, height: size * 1.1)
                    } else if state == .armed {
                        // Show subtle pulsing when armed
                        Circle()
                            .stroke(Color(hex: "#1ED760").opacity(0.3), lineWidth: 2)
                            .frame(width: size * 1.05, height: size * 1.05)
                            .scaleEffect(pulseAnimation ? 1.05 : 1.0)
                            .opacity(pulseAnimation ? 0.5 : 0.3)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)
                            .onAppear {
                                pulseAnimation = true
                            }
                    }
                }
            )
            .overlay(
                // Listening indicator - appears when actually recording (state is .listening)
                Group {
                    if case .listening = state {
                        VStack(spacing: 8) {
                            Image(systemName: "mic.fill")
                                .font(.title2)
                                .foregroundColor(Color(hex: "#1ED760"))
                                .symbolEffect(.pulse, options: .repeating)
                            
                            Text("Listening...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.8))
                                .shadow(color: Color(hex: "#1ED760").opacity(0.5), radius: 10)
                        )
                        .transition(.scale.combined(with: .opacity))
                        .offset(y: -size * 0.7) // Position above orb
                        .accessibilityLabel("Listening indicator")
                        .accessibilityValue("Listening, release to stop")
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: state)
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 1.5)
                    .sequenced(before: DragGesture(minimumDistance: 10))
                    .updating($isPressed) { value, state, _ in
                        switch value {
                        case .first(true):
                            // Long press started
                            if !state {
                                state = true
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scale = 0.9
                                }
                                // Start glow immediately
                                glowIntensity = 0.8
                                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                    glowIntensity = 1.0
                                }
                                // Don't show indicator here - wait for state to change to .listening
                                onLongPress()
                            }
                        case .second(true, let dragValue):
                            // Still pressing and dragging - check if drag distance is too large
                            if let drag = dragValue, abs(drag.translation.width) > 50 || abs(drag.translation.height) > 50 {
                                // User dragged too far - cancel
                                state = false
                                onLongPressEnd()
                                return
                            }
                            // Still pressing within acceptable range - keep recording
                            break
                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = 1.0
                        }
                        // Fade out glow
                        withAnimation(.easeOut(duration: 0.3)) {
                            glowIntensity = 0.0
                        }
                        // Contact lost - stop recording immediately
                        onLongPressEnd()
                    }
            )
            .onChange(of: state) { oldState, newState in
                updateScaleForState(newState)
                
                // Start error pulse animation if error state
                if case .error = newState {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseAnimation = true
                    }
                } else {
                    pulseAnimation = false
                }
                
                // Only show indicator when state is actually .listening (recording has started)
                if case .listening = newState {
                    // Recording started - show glow immediately and start pulsing
                    glowIntensity = 0.8
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        glowIntensity = 1.0
                    }
                } else if case .listening = oldState {
                    // Recording stopped - fade out glow
                    withAnimation(.easeOut(duration: 0.3)) {
                        glowIntensity = 0.0
                    }
                }
            }
            .onChange(of: isRecording) { oldValue, newValue in
                if newValue && !oldValue {
                    // Recording started - show glow immediately and start pulsing
                    glowIntensity = 0.8
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        glowIntensity = 1.0
                    }
                } else if !newValue && oldValue {
                    // Recording stopped - fade out glow
                    withAnimation(.easeOut(duration: 0.3)) {
                        glowIntensity = 0.0
                    }
                }
            }
            .onAppear {
                if isRecording {
                    glowIntensity = 0.8
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        glowIntensity = 1.0
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(orbAccessibilityLabel)
            .accessibilityHint(orbAccessibilityHint)
            .accessibilityValue(orbAccessibilityValue)
            .accessibilityAddTraits(orbAccessibilityTraits)
        }
    }
    
    private var orbAccessibilityLabel: String {
        "Recall orb"
    }
    
    private var orbAccessibilityHint: String {
        if isRecording {
            return "Recording. Release to stop recording."
        } else if showRecordingIndicator {
            return "Long press to record voice query, release to stop. Double tap to start new query."
        } else {
            return "Long press to record voice query, release to stop. Double tap to start new query."
        }
    }
    
    private var orbAccessibilityValue: String {
        switch state {
        case .idle:
            return "Idle"
        case .armed:
            return "Armed, ready to record"
        case .listening:
            return "Recording"
        case .thinking:
            return "Thinking"
        case .responding:
            return "Responding"
        case .done:
            return "Done"
        case .error:
            return "Error"
        }
    }
    
    private var orbAccessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = []
        if isRecording {
            traits.insert(.startsMediaSession)
            traits.insert(.updatesFrequently)
        }
        return traits
    }
    
    private var stateBasedOpacity: Double {
        switch state {
        case .idle:
            return 1.0
        case .armed:
            return 0.95
        case .listening:
            return 0.9
        case .thinking:
            return 0.85
        case .responding:
            return 0.9
        case .done:
            return 1.0
        case .error:
            return 0.7
        }
    }
    
    private var glowColors: [Color] {
        switch state {
        case .error:
            // Red glow for error state
            let errorGlow = pulseAnimation ? 0.4 : 0.2
            return [
                Color.red.opacity(errorGlow),
                Color.red.opacity(errorGlow * 0.5),
                Color.clear
            ]
        case .listening, .thinking:
            // Green glow for active states
            let activeGlow = isRecording ? glowIntensity : (state == .thinking ? 0.6 : 0.0)
            return [
                Color(hex: "#1ED760").opacity(0.3 * activeGlow),
                Color(hex: "#1ED760").opacity(0.15 * activeGlow),
                Color.clear
            ]
        default:
            // No glow for idle/done
            return [Color.clear, Color.clear, Color.clear]
        }
    }
    
    private func updateScaleForState(_ newState: RecallOrbState) {
        if !isPressed {
            withAnimation(.easeInOut(duration: 0.3)) {
                switch newState {
                case .idle:
                    scale = 1.0
                case .armed:
                    scale = 1.02 // Slight expand when armed
                case .listening(let level):
                    scale = 1.0 + level * 0.1
                case .thinking:
                    scale = 1.05
                case .responding:
                    scale = 1.03 // Subtle animation when responding
                case .done(let confidence):
                    if confidence >= 0.85 {
                        scale = 1.1
                    } else if confidence >= 0.60 {
                        scale = 1.05
                    } else {
                        scale = 1.0
                    }
                case .error:
                    scale = 0.95
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        VStack {
            RecallOrbView(state: RecallOrbState.idle, onLongPress: {}, onLongPressEnd: {})
            RecallOrbView(state: .listening(level: 0.5), onLongPress: {}, onLongPressEnd: {})
            RecallOrbView(state: .thinking, onLongPress: {}, onLongPressEnd: {})
            RecallOrbView(state: .done(confidence: 0.9), onLongPress: {}, onLongPressEnd: {})
        }
    }
}

