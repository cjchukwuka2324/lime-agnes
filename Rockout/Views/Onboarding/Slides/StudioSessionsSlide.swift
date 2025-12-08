import SwiftUI

struct StudioSessionsSlide: View {
    @State private var cardOffsets: [CGFloat] = [0, 10]
    @State private var cardScales: [CGFloat] = [1.0, 0.95]
    
    let sessions = [
        ("Studio Session", "Late Night Demo", 3),
        ("Collab", "Opium Wave Pack", 5)
    ]
    
    var body: some View {
        OnboardingSlideView(
            title: "Studio Sessions",
            subtitle: "Upload tracks, share snippets, and collaborate with others in private or group sessions."
        ) {
            ZStack {
                ForEach(Array(sessions.enumerated()), id: \.offset) { index, session in
                    SessionCard(
                        type: session.0,
                        title: session.1,
                        participantCount: session.2,
                        offset: cardOffsets[index],
                        scale: cardScales[index]
                    )
                    .offset(y: CGFloat(index * 20))
                    .zIndex(Double(2 - index))
                }
            }
            .frame(height: 180)
            .padding(.horizontal, 20)
        }
        .onAppear {
            // Parallax effect animation
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                cardOffsets = [0, 0]
                cardScales = [1.0, 1.0]
            }
        }
    }
}

struct SessionCard: View {
    let type: String
    let title: String
    let participantCount: Int
    let offset: CGFloat
    let scale: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Thumbnail placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.brandPurple.opacity(0.6), Color.brandBlue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.8))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(type)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Participant icons
                HStack(spacing: -8) {
                    ForEach(0..<min(participantCount, 3), id: \.self) { _ in
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.brandMagenta, Color.brandPurple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 2)
                            )
                    }
                    
                    if participantCount > 3 {
                        Text("+\(participantCount - 3)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.leading, 4)
                    }
                }
            }
            
            // Upload icon
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                
                Text("Upload")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.brandPurple.opacity(0.5), Color.brandBlue.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
        .offset(y: offset)
        .scaleEffect(scale)
        .shadow(color: Color.brandPurple.opacity(0.3), radius: 15)
    }
}




