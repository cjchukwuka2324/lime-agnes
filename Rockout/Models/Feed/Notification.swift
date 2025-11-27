import Foundation

enum NotificationType: String, Codable {
    case like
    case reply
    case follow
}

struct FeedNotification: Identifiable, Hashable {
    let id: String
    let type: NotificationType
    let fromUser: UserSummary
    let targetPost: Post?
    let targetUserId: String?
    let createdAt: Date
    let isRead: Bool
    
    init(
        id: String = UUID().uuidString,
        type: NotificationType,
        fromUser: UserSummary,
        targetPost: Post? = nil,
        targetUserId: String? = nil,
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.type = type
        self.fromUser = fromUser
        self.targetPost = targetPost
        self.targetUserId = targetUserId
        self.createdAt = createdAt
        self.isRead = isRead
    }
}

