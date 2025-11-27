import Foundation
import Supabase

@MainActor
class NotificationService {
    static let shared = NotificationService()
    
    private var notifications: [FeedNotification] = []
    private let queue = DispatchQueue(label: "NotificationServiceQueue", qos: .userInitiated)
    private let profileService = UserProfileService.shared
    
    private init() {}
    
    // MARK: - Current User Helper
    
    private func currentUserSummary() async -> UserSummary? {
        if let profile = try? await profileService.getCurrentUserProfile() {
            let displayName: String
            if let firstName = profile.firstName, let lastName = profile.lastName {
                displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            } else if let displayNameValue = profile.displayName, !displayNameValue.isEmpty {
                displayName = displayNameValue
            } else {
                let email = SupabaseService.shared.client.auth.currentUser?.email ?? "User"
                displayName = email.components(separatedBy: "@").first ?? "User"
            }
            
            let handle: String
            if let email = SupabaseService.shared.client.auth.currentUser?.email {
                let emailPrefix = email.components(separatedBy: "@").first ?? "user"
                handle = "@\(emailPrefix)"
            } else if let firstName = profile.firstName {
                handle = "@\(firstName.lowercased())"
            } else {
                handle = "@user"
            }
            
            let initials: String
            if let firstName = profile.firstName, let lastName = profile.lastName {
                let firstInitial = String(firstName.prefix(1)).uppercased()
                let lastInitial = String(lastName.prefix(1)).uppercased()
                initials = "\(firstInitial)\(lastInitial)"
            } else {
                initials = String(displayName.prefix(2)).uppercased()
            }
            
            guard let userId = SupabaseService.shared.client.auth.currentUser?.id else {
                return nil
            }
            
            return UserSummary(
                id: userId.uuidString,
                displayName: displayName,
                handle: handle,
                avatarInitials: initials
            )
        }
        return nil
    }
    
    // MARK: - Fetch Notifications
    
    func fetchNotifications() async -> [FeedNotification] {
        guard let currentUser = await currentUserSummary() else {
            return []
        }
        
        return await withCheckedContinuation { continuation in
            queue.async {
                // Filter notifications for current user
                let userNotifications = self.notifications.filter { notification in
                    // For likes/replies, check if target post belongs to current user
                    if let targetPost = notification.targetPost {
                        return targetPost.author.id == currentUser.id
                    }
                    // For follows, check if targetUserId is current user
                    if let targetUserId = notification.targetUserId {
                        return targetUserId == currentUser.id
                    }
                    return false
                }
                .sorted(by: { $0.createdAt > $1.createdAt })
                
                continuation.resume(returning: userNotifications)
            }
        }
    }
    
    // MARK: - Create Notifications
    
    func createLikeNotification(from user: UserSummary, for post: Post) {
        queue.async {
            let notification = FeedNotification(
                type: .like,
                fromUser: user,
                targetPost: post
            )
            self.notifications.append(notification)
            
            // Post notification to NotificationCenter
            NotificationCenter.default.post(name: .notificationReceived, object: nil)
        }
    }
    
    func createReplyNotification(from user: UserSummary, for post: Post) {
        queue.async {
            let notification = FeedNotification(
                type: .reply,
                fromUser: user,
                targetPost: post
            )
            self.notifications.append(notification)
            
            NotificationCenter.default.post(name: .notificationReceived, object: nil)
        }
    }
    
    func createFollowNotification(from user: UserSummary, targetUserId: String) {
        queue.async {
            let notification = FeedNotification(
                type: .follow,
                fromUser: user,
                targetUserId: targetUserId
            )
            self.notifications.append(notification)
            
            NotificationCenter.default.post(name: .notificationReceived, object: nil)
        }
    }
    
    // MARK: - Mark as Read
    
    func markAsRead(_ notificationId: String) {
        queue.async {
            if let index = self.notifications.firstIndex(where: { $0.id == notificationId }) {
                var notification = self.notifications[index]
                notification = FeedNotification(
                    id: notification.id,
                    type: notification.type,
                    fromUser: notification.fromUser,
                    targetPost: notification.targetPost,
                    targetUserId: notification.targetUserId,
                    createdAt: notification.createdAt,
                    isRead: true
                )
                self.notifications[index] = notification
            }
        }
    }
    
    // MARK: - Unread Count
    
    func getUnreadCount() async -> Int {
        guard let currentUser = await currentUserSummary() else {
            return 0
        }
        
        return await withCheckedContinuation { continuation in
            queue.async {
                let count = self.notifications.filter { notification in
                    if notification.isRead { return false }
                    
                    if let targetPost = notification.targetPost {
                        return targetPost.author.id == currentUser.id
                    }
                    if let targetUserId = notification.targetUserId {
                        return targetUserId == currentUser.id
                    }
                    return false
                }.count
                
                continuation.resume(returning: count)
            }
        }
    }
}

