import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NotificationsViewModel()
    @State private var selectedPostId: String?
    @State private var selectedUserId: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Solid black background
                 Color.black.ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading notifications...")
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else if viewModel.filteredNotifications.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text(viewModel.selectedFilter == .all ? "No Notifications" : "No \(viewModel.selectedFilter.rawValue) Notifications")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        
                        Text(viewModel.selectedFilter == .all 
                             ? "When someone amps, adlibs, or follows you, you'll see it here"
                             : "Try changing the filter to see more notifications")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(viewModel.groupedNotifications) { group in
                                VStack(alignment: .leading, spacing: 12) {
                                    // Section header
                                    Text(group.title)
                                        .font(.headline)
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.horizontal, 20)
                                    
                                    // Notifications in group
                                    ForEach(group.notifications) { notification in
                                        NotificationCard(notification: notification)
                                            .padding(.horizontal, 20)
                                            .onTapGesture {
                                                handleNotificationTap(notification)
                                            }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                if notification.readAt == nil {
                                                    Button {
                                                        Task {
                                                            await viewModel.markAsRead(notification.id)
                                                        }
                                                    } label: {
                                                        Label("Mark Read", systemImage: "checkmark.circle")
                                                    }
                                                    .tint(Color(hex: "#1ED760"))
                                                }
                                            }
                                    }
                                }
                            }
                            
                            // Load more indicator
                            if viewModel.isLoadingMore {
                                ProgressView()
                                    .tint(.white)
                                    .padding()
                            } else if viewModel.hasMorePages {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        Task {
                                            await viewModel.loadMore()
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                // Ensure navigation bar is always opaque black
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .black
                appearance.shadowColor = .clear
                
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
                UINavigationBar.appearance().compactAppearance = appearance
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(NotificationFilter.allCases, id: \.self) { filter in
                            Button {
                                viewModel.selectedFilter = filter
                            } label: {
                                HStack {
                                    Text(filter.rawValue)
                                    if viewModel.selectedFilter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button("Mark All Read") {
                            Task {
                                await viewModel.markAllAsRead()
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(.white)
                    }
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
            // RockList feature removed - no navigation needed
            break
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
                .frame(width: 56, height: 56)
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
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: iconName)
                        .foregroundColor(.white)
                        .font(.system(size: 24))
                }
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
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
                    .frame(width: 10, height: 10)
            }
        }
        .padding(16)
        .glassMorphism()
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
