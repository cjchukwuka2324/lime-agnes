import SwiftUI

struct RecallTabBarIcon: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { timeline in
            let time = timeline.date.timeIntervalSince1970
            let animationPhase = CGFloat(time.truncatingRemainder(dividingBy: 1.5) / 1.5 * 2 * .pi)
            
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#1ED760").opacity(0.3),
                                Color(hex: "#1ED760").opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 12
                        )
                    )
                    .frame(width: 24, height: 24)
                    .scaleEffect(1.0 + sin(animationPhase) * 0.2)
                
                // Inner orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: "#1ED760").opacity(0.9),
                                Color(hex: "#1ED760").opacity(0.6)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 8
                        )
                    )
                    .frame(width: 16, height: 16)
                    .scaleEffect(1.0 + sin(animationPhase + .pi / 4) * 0.15)
                
                // Sparkles
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 2)
                        .offset(
                            x: cos(animationPhase + CGFloat(index) * 2 * .pi / 3) * 10,
                            y: sin(animationPhase + CGFloat(index) * 2 * .pi / 3) * 10
                        )
                        .opacity(0.5 + sin(animationPhase + CGFloat(index) * 2 * .pi / 3) * 0.5)
                }
            }
            .frame(width: 30, height: 30)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        RecallTabBarIcon()
    }
}
