import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NotificationsViewModel()
    
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
                        
                        Text("When someone likes or comments on your posts, you'll see it here")
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
                                NotificationRow(notification: notification)
                                    .padding(.horizontal, 20)
                                    .onTapGesture {
                                        viewModel.markAsRead(notification.id)
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                Task {
                    await viewModel.load()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notificationReceived)) { _ in
                Task {
                    await viewModel.load()
                }
            }
        }
    }
}

struct NotificationRow: View {
    let notification: FeedNotification
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
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
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(notificationText)
                    .font(.body)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                
                Text(notification.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Unread indicator
            if !notification.isRead {
                Circle()
                    .fill(Color(hex: "#1ED760"))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(16)
        .glassMorphism()
    }
    
    private var iconName: String {
        switch notification.type {
        case .like:
            return "heart.fill"
        case .reply:
            return "bubble.left.fill"
        case .follow:
            return "person.badge.plus.fill"
        }
    }
    
    private var notificationText: String {
        let userName = notification.fromUser.displayName
        switch notification.type {
        case .like:
            return "\(userName) liked your post"
        case .reply:
            return "\(userName) replied to your post"
        case .follow:
            return "\(userName) started following you"
        }
    }
}

@MainActor
class NotificationsViewModel: ObservableObject {
    @Published var notifications: [FeedNotification] = []
    @Published var isLoading = false
    
    func load() async {
        isLoading = true
        defer { isLoading = false }
        
        notifications = await NotificationService.shared.fetchNotifications()
    }
    
    func markAsRead(_ notificationId: String) {
        NotificationService.shared.markAsRead(notificationId)
        // Update local state
        if let index = notifications.firstIndex(where: { $0.id == notificationId }) {
            var notification = notifications[index]
            notification = FeedNotification(
                id: notification.id,
                type: notification.type,
                fromUser: notification.fromUser,
                targetPost: notification.targetPost,
                targetUserId: notification.targetUserId,
                createdAt: notification.createdAt,
                isRead: true
            )
            notifications[index] = notification
        }
    }
}

