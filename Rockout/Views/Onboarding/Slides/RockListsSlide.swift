import SwiftUI

struct RockListsSlide: View {
    @State private var highlightScale: CGFloat = 1.0
    
    let leaderboardEntries = [
        ("@melodicwave", "98,204", 1),
        ("@kaidotunes", "84,992", 2),
        ("@sxnnyblue", "73,113", 3)
    ]
    
    var body: some View {
        OnboardingSlideView(
            title: "Climb RockLists",
            subtitle: "Compete with other fans to become a top listener for your favorite artists."
        ) {
            VStack(spacing: 16) {
                ForEach(Array(leaderboardEntries.enumerated()), id: \.offset) { index, entry in
                    LeaderboardRow(
                        rank: entry.2,
                        username: entry.0,
                        streams: entry.1,
                        isHighlighted: index == 0,
                        scale: index == 0 ? highlightScale : 1.0
                    )
                }
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                highlightScale = 1.05
            }
        }
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let username: String
    let streams: String
    let isHighlighted: Bool
    let scale: CGFloat
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank badge
            ZStack {
                Circle()
                    .fill(
                        isHighlighted ?
                        LinearGradient(
                            colors: [Color.brandPurple, Color.brandBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Text("#\(rank)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            .shadow(color: isHighlighted ? Color.brandPurple.opacity(0.6) : Color.clear, radius: 8)
            
            // Username
            Text(username)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            // Stream count
            Text("\(streams) streams")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            // Progress bar
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: isHighlighted ? [Color.brandPurple, Color.brandBlue] : [Color.white.opacity(0.3), Color.white.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 60, height: 4)
                .shadow(color: isHighlighted ? Color.brandPurple.opacity(0.5) : Color.clear, radius: 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isHighlighted ? 0.15 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isHighlighted ?
                            LinearGradient(
                                colors: [Color.brandPurple.opacity(0.8), Color.brandBlue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(0.2), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isHighlighted ? 2 : 1
                        )
                )
        )
        .scaleEffect(scale)
        .shadow(color: isHighlighted ? Color.brandPurple.opacity(0.3) : Color.clear, radius: 12)
    }
}




