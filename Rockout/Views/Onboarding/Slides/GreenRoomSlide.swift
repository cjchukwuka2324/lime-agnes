import SwiftUI

struct GreenRoomSlide: View {
    @State private var cardOffsets: [CGFloat] = [0, -10, -20]
    @State private var cardOpacities: [Double] = [1.0, 0.8, 0.6]
    
    let feedPosts = [
        ("@melodicwave", "late night drive playlist", "🎵"),
        ("@kaidotunes", "pre-show warmup", "🎸"),
        ("@sxnnyblue", "vibing to this rn", "🎧")
    ]
    
    var body: some View {
        OnboardingSlideView(
            title: "GreenRoom",
            subtitle: "A live timeline where you and your friends share what you're listening to and how it feels."
        ) {
            ZStack {
                ForEach(Array(feedPosts.enumerated()), id: \.offset) { index, post in
                    FeedPostCard(
                        username: post.0,
                        caption: post.1,
                        emoji: post.2,
                        offset: cardOffsets[index],
                        opacity: cardOpacities[index]
                    )
                    .offset(y: CGFloat(index * 15))
                    .zIndex(Double(3 - index))
                }
            }
            .frame(height: 200)
            .padding(.horizontal, 20)
        }
        .onAppear {
            // Staggered animation
            for index in 0..<cardOffsets.count {
                withAnimation(.easeOut(duration: 0.6).delay(Double(index) * 0.1)) {
                    cardOffsets[index] = 0
                    cardOpacities[index] = 1.0
                }
            }
        }
    }
}

struct FeedPostCard: View {
    let username: String
    let caption: String
    let emoji: String
    let offset: CGFloat
    let opacity: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.brandPurple, Color.brandBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Text(String(username.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Username
                Text(username)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            // Caption with emoji
            HStack(spacing: 8) {
                Text(emoji)
                    .font(.system(size: 20))
                
                Text(caption)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Interaction icons
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                        .font(.system(size: 12))
                    Text("12")
                        .font(.system(size: 12))
                }
                .foregroundColor(.white.opacity(0.6))
                
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 12))
                    Text("3")
                        .font(.system(size: 12))
                }
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
                                colors: [Color.brandPurple.opacity(0.3), Color.brandBlue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .offset(y: offset)
        .opacity(opacity)
        .shadow(color: Color.brandPurple.opacity(0.2), radius: 10)
    }
}




