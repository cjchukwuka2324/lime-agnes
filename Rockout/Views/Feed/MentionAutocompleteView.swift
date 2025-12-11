import SwiftUI

/// Autocomplete dropdown for @mentions
struct MentionAutocompleteView: View {
    let suggestions: [UserSummary]
    let onSelect: (UserSummary) -> Void
    
    var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(suggestions.prefix(5)) { user in
                    Button {
                        onSelect(user)
                    } label: {
                        HStack(spacing: 12) {
                            // Avatar
                            Group {
                                if let pictureURL = user.profilePictureURL {
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
                                            avatarFallback(user: user)
                                        @unknown default:
                                            avatarFallback(user: user)
                                        }
                                    }
                                } else {
                                    avatarFallback(user: user)
                                }
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                            
                            // Name and handle
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                
                                Text("@\(user.handle)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.05))
                    }
                    .buttonStyle(.plain)
                    
                    if user.id != suggestions.prefix(5).last?.id {
                        Divider()
                            .background(Color.white.opacity(0.1))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#1a1a1a"))
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private func avatarFallback(user: UserSummary) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1ED760").opacity(0.3),
                            Color(hex: "#1DB954").opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(user.avatarInitials)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}


