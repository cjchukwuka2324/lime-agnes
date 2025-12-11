import SwiftUI

struct MutualFollowSuggestionCard: View {
    let suggestion: MutualFollowSuggestion
    let onFollowChanged: ((Bool) -> Void)?
    
    @State private var isFollowing: Bool = false
    @State private var isUpdatingFollow = false
    
    private let followService = FollowService.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Group {
                if let pictureURL = suggestion.user.profilePictureURL {
                    AsyncImage(url: pictureURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white.opacity(0.6))
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            avatarFallback
                        @unknown default:
                            avatarFallback
                        }
                    }
                } else {
                    avatarFallback
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.user.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(suggestion.user.handle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                
                // Mutual followers badge
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("\(suggestion.mutualCount) mutual follower\(suggestion.mutualCount == 1 ? "" : "s")")
                        .font(.caption2)
                }
                .foregroundColor(Color(hex: "#1ED760"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "#1ED760").opacity(0.2))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Follow Button
            Button {
                Task {
                    await toggleFollow(userId: UUID(uuidString: suggestion.user.id) ?? UUID())
                }
            } label: {
                if isUpdatingFollow {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 80, height: 32)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isFollowing ? .white : .black)
                        .frame(width: 80, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isFollowing ? Color.white.opacity(0.2) : Color(hex: "#1ED760"))
                        )
                }
            }
            .disabled(isUpdatingFollow)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            isFollowing = suggestion.user.isFollowing
        }
    }
    
    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1DB954"),
                            Color(hex: "#1ED760")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(suggestion.user.avatarInitials)
                .font(.title3.bold())
                .foregroundColor(.white)
        }
    }
    
    private func toggleFollow(userId: UUID) async {
        isUpdatingFollow = true
        defer { isUpdatingFollow = false }
        
        do {
            if isFollowing {
                try await followService.unfollow(userId: userId)
                isFollowing = false
                onFollowChanged?(false)
            } else {
                try await followService.follow(userId: userId)
                isFollowing = true
                onFollowChanged?(true)
            }
        } catch {
            print("Failed to toggle follow: \(error)")
        }
    }
}

