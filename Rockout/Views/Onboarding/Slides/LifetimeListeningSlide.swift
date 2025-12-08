import SwiftUI

struct LifetimeListeningSlide: View {
    @State private var animationOffset: CGFloat = 0
    @State private var glowIntensity: Double = 0.5
    
    let years = [2019, 2020, 2021, 2022, 2023, 2024]
    
    var body: some View {
        OnboardingSlideView(
            title: "Your lifetime listening story",
            subtitle: "Rockout turns your streams into a living timeline of your music taste."
        ) {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        Color.brandPurple.opacity(0.2),
                        Color.brandBlue.opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 200)
                
                // Waveform path
                TimelineWaveformView(animationOffset: $animationOffset)
                    .frame(height: 200)
                
                // Year markers with glow
                HStack(spacing: 0) {
                    ForEach(years, id: \.self) { year in
                        VStack {
                            Circle()
                                .fill(Color.brandPurple)
                                .frame(width: 8, height: 8)
                                .shadow(color: Color.brandPurple.opacity(glowIntensity), radius: 8)
                            
                            Text("\(year)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 100)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: true)) {
                animationOffset = 20
            }
            
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                glowIntensity = 1.0
            }
        }
    }
}

struct TimelineWaveformView: View {
    @Binding var animationOffset: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let centerY = height / 2
                
                // Create a wavy path
                path.move(to: CGPoint(x: 0, y: centerY))
                
                for x in stride(from: 0, through: width, by: 4) {
                    let normalizedX = x / width
                    let wave = sin(normalizedX * .pi * 4 + animationOffset * 0.1) * 30
                    let y = centerY + wave
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(
                LinearGradient(
                    colors: [Color.brandPurple, Color.brandBlue, Color.brandMagenta],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: Color.brandPurple.opacity(0.5), radius: 10)
            .blur(radius: 1)
        }
    }
}




