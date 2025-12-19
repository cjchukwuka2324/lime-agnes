import SwiftUI

struct RecallOrbView: View {
    let state: RecallOrbState
    let onLongPress: () -> Void
    let onLongPressEnd: () -> Void
    
    @State private var isPressed = false
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // GIF Orb
            if let gifPath = Bundle.main.path(forResource: "recallOrb", ofType: "GIF") {
                GifImage("recallOrb.GIF")
                    .frame(width: 200, height: 200)
                    .scaleEffect(scale)
                    .opacity(stateBasedOpacity)
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
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .scaleEffect(scale)
            }
        }
        .frame(width: 200, height: 200)
        .gesture(
            LongPressGesture(minimumDuration: 3.0)
                .onChanged { _ in
                    isPressed = true
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scale = 0.9
                    }
                    onLongPress()
                }
                .onEnded { _ in
                    isPressed = false
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scale = 1.0
                    }
                    onLongPressEnd()
                }
        )
        .onChange(of: state) { _, newState in
            updateScaleForState(newState)
        }
    }
    
    private var stateBasedOpacity: Double {
        switch state {
        case .idle:
            return 1.0
        case .listening:
            return 0.9
        case .thinking:
            return 0.85
        case .done:
            return 1.0
        case .error:
            return 0.7
        }
    }
    
    private func updateScaleForState(_ newState: RecallOrbState) {
        if !isPressed {
            withAnimation(.easeInOut(duration: 0.3)) {
                switch newState {
                case .idle:
                    scale = 1.0
                case .listening(let level):
                    scale = 1.0 + level * 0.1
                case .thinking:
                    scale = 1.05
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
            RecallOrbView(state: .idle, onLongPress: {}, onLongPressEnd: {})
            RecallOrbView(state: .listening(level: 0.5), onLongPress: {}, onLongPressEnd: {})
            RecallOrbView(state: .thinking, onLongPress: {}, onLongPressEnd: {})
            RecallOrbView(state: .done(confidence: 0.9), onLongPress: {}, onLongPressEnd: {})
        }
    }
}

