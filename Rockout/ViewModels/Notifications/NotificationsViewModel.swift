import Foundation
import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let notificationService: NotificationService
    
    init(notificationService: NotificationService = SupabaseNotificationService.shared) {
        self.notificationService = notificationService
    }
    
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let fetchedNotifications = try await notificationService.fetchNotifications(limit: 50, before: nil)
            // Deduplicate notifications - keep only unique by ID and remove duplicates with same type/post within 1 minute
            notifications = deduplicateNotifications(fetchedNotifications)
            await refreshUnreadCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// Removes duplicate notifications based on content and timing
    private func deduplicateNotifications(_ notifications: [AppNotification]) -> [AppNotification] {
        var seen: Set<String> = []
        var result: [AppNotification] = []
        
        for notification in notifications {
            // Create a unique key based on type, post, actor, and time window (within 1 minute)
            let timeKey = Int(notification.createdAt.timeIntervalSince1970 / 60) // 1-minute buckets
            let postKey = notification.postId ?? "none"
            let actorKey = notification.actor?.id ?? "none"
            let uniqueKey = "\(notification.type)_\(postKey)_\(actorKey)_\(timeKey)"
            
            if !seen.contains(uniqueKey) {
                seen.insert(uniqueKey)
                result.append(notification)
            }
        }
        
        return result
    }
    
    func markAsRead(_ id: String) async {
        do {
            try await notificationService.markAsRead(id: id)
            // Update local state
            if let index = notifications.firstIndex(where: { $0.id == id }) {
                var updated = notifications[index]
                notifications[index] = AppNotification(
                    id: updated.id,
                    type: updated.type,
                    message: updated.message,
                    createdAt: updated.createdAt,
                    readAt: Date(),
                    actor: updated.actor,
                    postId: updated.postId,
                    rocklistId: updated.rocklistId,
                    oldRank: updated.oldRank,
                    newRank: updated.newRank
                )
            }
            await refreshUnreadCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func markAllAsRead() async {
        do {
            try await notificationService.markAllAsRead()
            // Update local state
            notifications = notifications.map { notification in
                AppNotification(
                    id: notification.id,
                    type: notification.type,
                    message: notification.message,
                    createdAt: notification.createdAt,
                    readAt: notification.readAt ?? Date(),
                    actor: notification.actor,
                    postId: notification.postId,
                    rocklistId: notification.rocklistId,
                    oldRank: notification.oldRank,
                    newRank: notification.newRank
                )
            }
            await refreshUnreadCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func refreshUnreadCount() async {
        do {
            unreadCount = try await notificationService.getUnreadCount()
        } catch {
            // Silently fail - unread count is not critical
        }
    }
}

