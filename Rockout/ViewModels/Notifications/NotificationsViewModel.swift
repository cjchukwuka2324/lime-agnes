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
            notifications = try await notificationService.fetchNotifications(limit: 50, before: nil)
            await refreshUnreadCount()
        } catch {
            errorMessage = error.localizedDescription
        }
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

