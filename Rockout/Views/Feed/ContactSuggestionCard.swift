import SwiftUI
import MessageUI

struct ContactSuggestionCard: View {
    let contact: MatchedContact
    let isInvite: Bool
    let onFollowChanged: ((Bool) -> Void)?
    var onInvite: (() -> Void)?
    
    @State private var isFollowing: Bool = false
    @State private var isUpdatingFollow = false
    @State private var showMessageComposer = false
    
    private let followService = FollowService.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
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
                .frame(width: 56, height: 56)
                .overlay(
                    Text(contact.contactName.prefix(2).uppercased())
                        .font(.title3.bold())
                        .foregroundColor(.white)
                )
            
            // Contact Info
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.contactName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let user = contact.matchedUser {
                    Text("@\(user.handle)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                } else {
                    if let phone = contact.contactPhone {
                        Text(phone)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                // "From Contacts" badge
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.caption2)
                    Text("From Contacts")
                        .font(.caption2)
                }
                .foregroundColor(Color(hex: "#1ED760"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "#1ED760").opacity(0.2))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Action Button
            if isInvite {
                Button {
                    onInvite?()
                } label: {
                    Text("Invite")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(width: 80, height: 32)
                        .background(Color(hex: "#1ED760"))
                        .cornerRadius(16)
                }
            } else if let user = contact.matchedUser {
                Button {
                    Task {
                        await toggleFollow(userId: UUID(uuidString: user.id) ?? UUID())
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
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            if let user = contact.matchedUser {
                isFollowing = user.isFollowing
            }
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

