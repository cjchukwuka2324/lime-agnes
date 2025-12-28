import Foundation
import SwiftUI

enum NotificationFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case follows = "Follows"
    case likes = "Likes"
    case replies = "Replies"
    case mentions = "Mentions"
    
    var typeFilter: String? {
        switch self {
        case .all: return nil
        case .unread: return nil
        case .follows: return "new_follower"
        case .likes: return "post_like"
        case .replies: return "post_reply"
        case .mentions: return "post_mention"
        }
    }
}

struct NotificationGroup: Identifiable {
    let id: String
    let title: String
    let notifications: [AppNotification]
}

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var notifications: [AppNotification] = []
    @Published var unreadCount: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedFilter: NotificationFilter = .all
    @Published var hasMorePages = true
    @Published var isLoadingMore = false
    
    private let notificationService: NotificationService
    private var lastLoadedDate: Date?
    private let pageSize = 50
    
    init(notificationService: NotificationService = SupabaseNotificationService.shared) {
        self.notificationService = notificationService
    }
    
    func load() async {
        isLoading = true
        errorMessage = nil
        lastLoadedDate = nil
        hasMorePages = true
        defer { isLoading = false }
        
        do {
            let fetchedNotifications = try await notificationService.fetchNotifications(limit: pageSize, before: nil)
            // Deduplicate notifications - keep only unique by ID and remove duplicates with same type/post within 1 minute
            notifications = deduplicateNotifications(fetchedNotifications)
            lastLoadedDate = notifications.last?.createdAt
            hasMorePages = fetchedNotifications.count >= pageSize
            // Count unread from deduplicated list to match displayed notifications
            refreshUnreadCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func loadMore() async {
        guard hasMorePages && !isLoadingMore && !isLoading else { return }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            let fetchedNotifications = try await notificationService.fetchNotifications(limit: pageSize, before: lastLoadedDate)
            let deduplicated = deduplicateNotifications(fetchedNotifications)
            notifications.append(contentsOf: deduplicated)
            lastLoadedDate = notifications.last?.createdAt
            hasMorePages = fetchedNotifications.count >= pageSize
            refreshUnreadCount()
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
            // Count unread from deduplicated list
            refreshUnreadCount()
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
            // Count unread from deduplicated list
            refreshUnreadCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func refreshUnreadCount() {
        // Count unread from the deduplicated notifications list to match what's displayed
        unreadCount = notifications.filter { $0.readAt == nil }.count
    }
    
    // MARK: - Filtered Notifications
    
    var filteredNotifications: [AppNotification] {
        var filtered = notifications
        
        // Apply type filter
        if let typeFilter = selectedFilter.typeFilter {
            filtered = filtered.filter { $0.type == typeFilter }
        }
        
        // Apply unread filter
        if selectedFilter == .unread {
            filtered = filtered.filter { $0.readAt == nil }
        }
        
        return filtered
    }
    
    // MARK: - Grouped Notifications
    
    var groupedNotifications: [NotificationGroup] {
        let filtered = filteredNotifications
        let calendar = Calendar.current
        let now = Date()
        
        var groups: [NotificationGroup] = []
        var today: [AppNotification] = []
        var yesterday: [AppNotification] = []
        var thisWeek: [AppNotification] = []
        var older: [AppNotification] = []
        
        for notification in filtered {
            let daysAgo = calendar.dateComponents([.day], from: notification.createdAt, to: now).day ?? 0
            
            if calendar.isDateInToday(notification.createdAt) {
                today.append(notification)
            } else if calendar.isDateInYesterday(notification.createdAt) {
                yesterday.append(notification)
            } else if daysAgo <= 7 {
                thisWeek.append(notification)
            } else {
                older.append(notification)
            }
        }
        
        if !today.isEmpty {
            groups.append(NotificationGroup(id: "today", title: "Today", notifications: today))
        }
        if !yesterday.isEmpty {
            groups.append(NotificationGroup(id: "yesterday", title: "Yesterday", notifications: yesterday))
        }
        if !thisWeek.isEmpty {
            groups.append(NotificationGroup(id: "thisWeek", title: "This Week", notifications: thisWeek))
        }
        if !older.isEmpty {
            groups.append(NotificationGroup(id: "older", title: "Older", notifications: older))
        }
        
        return groups
    }
}

