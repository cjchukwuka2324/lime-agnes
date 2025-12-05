import SwiftUI

struct ParentPostReferenceView: View {
    let parentPost: PostSummary
    let onTap: (() -> Void)?
    
    init(parentPost: PostSummary, onTap: (() -> Void)? = nil) {
        self.parentPost = parentPost
        self.onTap = onTap
    }
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 8) {
            // Small avatar with profile picture
            Group {
                if let profilePictureURL = parentPost.author.profilePictureURL {
                    AsyncImage(url: profilePictureURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Text(parentPost.author.avatarInitials)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.white)
                            )
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(parentPost.author.avatarInitials)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                        )
                }
            }
            
            // Author name
            Text(parentPost.author.displayName)
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.8))
            
            // Post preview
            Text(parentPost.text.isEmpty ? "Media post" : parentPost.text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
            
            Spacer()
            
            Image(systemName: "arrowshape.turn.up.right.fill")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        }
        .buttonStyle(.plain)
    }
}

