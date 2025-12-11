import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NotificationsViewModel()
    @State private var selectedPostId: String?
    @State private var selectedUserId: String?
    @State private var selectedArtistId: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Green gradient background
                LinearGradient(
                    colors: [
                        Color(hex: "#050505"),
                        Color(hex: "#0C7C38"),
                        Color(hex: "#1DB954"),
                        Color(hex: "#1ED760"),
                        Color(hex: "#050505")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading notifications...")
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else if viewModel.notifications.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("No Notifications")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        
                        Text("When someone amps, adlibs, or follows you, you'll see it here")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.notifications) { notification in
                                NotificationCard(notification: notification)
                                    .padding(.horizontal, 20)
                                    .onTapGesture {
                                        handleNotificationTap(notification)
                                    }
                            }
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Mark All Read") {
                        Task {
                            await viewModel.markAllAsRead()
                        }
                    }
                    .foregroundColor(.white)
                    .font(.subheadline)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
            .navigationDestination(item: $selectedPostId) { postId in
                PostDetailView(postId: postId, service: SupabaseFeedService.shared)
            }
            .navigationDestination(item: $selectedUserId) { userId in
                UserProfileDetailView(userId: UUID(uuidString: userId) ?? UUID())
            }
            .navigationDestination(item: $selectedArtistId) { artistId in
                RockListView(artistId: artistId)
            }
        }
    }
    
    private func handleNotificationTap(_ notification: AppNotification) {
        // Mark as read
        Task {
            await viewModel.markAsRead(notification.id)
        }
        
        // Navigate based on type
        switch notification.type {
        case "new_follower":
            if let actorId = notification.actor?.id {
                selectedUserId = actorId
            }
        case "post_like", "post_reply", "new_post", "post_echo", "post_mention":
            if let postId = notification.postId {
                selectedPostId = postId
            }
        case "rocklist_rank":
            if let artistId = notification.rocklistId {
                selectedArtistId = artistId
            }
        default:
            break
        }
    }
}

struct NotificationCard: View {
    let notification: AppNotification
    
    var body: some View {
        HStack(spacing: 12) {
            // Actor Avatar
            if let actor = notification.actor {
                AsyncImage(url: actor.profilePictureURL) { phase in
                    switch phase {
                    case .empty:
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
                                Text(actor.avatarInitials)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
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
                                Text(actor.avatarInitials)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                // Fallback icon
                ZStack {
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
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: iconName)
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.message.transformedForGreenRoom())
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                
                Text(timeAgoString(from: notification.createdAt))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Unread indicator
            if notification.readAt == nil {
                Circle()
                    .fill(Color(hex: "#1ED760"))
                    .frame(width: 8, height: 8)
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
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private var iconName: String {
        switch notification.type {
        case "new_follower":
            return "person.badge.plus.fill"
        case "post_like":
            return "bolt.fill" // Changed from heart.fill to match Amp branding
        case "post_reply":
            return "bubble.left.fill"
        case "post_echo":
            return "arrow.2.squarepath" // Echo/Repost icon
        case "post_mention":
            return "at" // Mention icon
        case "new_post":
            return "square.and.pencil"
        case "rocklist_rank":
            return "chart.bar.fill"
        default:
            return "bell.fill"
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Extension to make String Identifiable for navigation
extension String: @retroactive Identifiable {
    public var id: String { self }
}
