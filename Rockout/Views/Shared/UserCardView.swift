import SwiftUI

struct UserCardView: View {
    let user: UserSummary
    let onFollowToggle: ((UserSummary) -> Void)?
    @State private var isFollowing: Bool
    @State private var isUpdatingFollow = false
    
    private let social = SupabaseSocialGraphService.shared
    
    init(user: UserSummary, onFollowToggle: ((UserSummary) -> Void)? = nil) {
        self.user = user
        self.onFollowToggle = onFollowToggle
        self._isFollowing = State(initialValue: user.isFollowing)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Group {
                if let imageURL = user.profilePictureURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            defaultAvatar
                        @unknown default:
                            defaultAvatar
                        }
                    }
                } else {
                    defaultAvatar
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(user.handle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Follow Button
            if let onFollowToggle = onFollowToggle {
                Button {
                    Task {
                        await toggleFollow()
                        onFollowToggle(user)
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
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onAppear {
            // Sync internal state with user object when view appears
            isFollowing = user.isFollowing
        }
        .onChange(of: user.isFollowing) { _, newValue in
            // Update internal state when user object changes
            isFollowing = newValue
        }
    }
    
    private var defaultAvatar: some View {
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
            .overlay(
                Text(user.avatarInitials)
                    .font(.title3.bold())
                    .foregroundColor(.white)
            )
    }
    
    private func toggleFollow() async {
        isUpdatingFollow = true
        defer { isUpdatingFollow = false }
        
        do {
            if isFollowing {
                try await social.unfollow(userId: user.id)
                isFollowing = false
            } else {
                try await social.follow(userId: user.id)
                isFollowing = true
            }
        } catch {
            print("Failed to toggle follow: \(error)")
        }
    }
}
