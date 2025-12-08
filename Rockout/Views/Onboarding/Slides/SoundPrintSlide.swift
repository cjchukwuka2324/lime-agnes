import SwiftUI

struct SoundPrintSlide: View {
    @State private var barHeights: [CGFloat] = [0, 0, 0, 0, 0]
    @State private var hasAnimated = false
    
    let stats = [
        ("Top Artist", "Rema"),
        ("Top Track", "Nights"),
        ("Streams", "1,234")
    ]
    
    var body: some View {
        OnboardingSlideView(
            title: "SoundPrint",
            subtitle: "See your music stats, top artists, and listening habits in one place."
        ) {
            VStack(spacing: 24) {
                // Stats dashboard card
                VStack(spacing: 20) {
                    // Stats rows
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                        HStack {
                            Text(stat.0)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Spacer()
                            
                            Text(stat.1)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Divider()
                        .background(Color.white.opacity(0.2))
                    
                    // Animated bar chart
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(0..<5, id: \.self) { index in
                            VStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.brandPurple, Color.brandBlue],
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                    .frame(width: 30, height: barHeights[index])
                                    .shadow(color: Color.brandPurple.opacity(0.5), radius: 4)
                                
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .frame(height: 120)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.brandPurple.opacity(0.5), Color.brandBlue.opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                )
                .shadow(color: Color.brandPurple.opacity(0.2), radius: 20)
            }
        }
        .onAppear {
            if !hasAnimated {
                hasAnimated = true
                let targetHeights: [CGFloat] = [80, 60, 100, 45, 70]
                
                withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                    barHeights = targetHeights
                }
            }
        }
    }
}




