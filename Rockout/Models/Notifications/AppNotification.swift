import Foundation

/// Represents a notification in the RockOut app
struct AppNotification: Identifiable, Hashable, Codable {
    let id: String
    let type: String  // 'new_follower', 'post_like', 'post_reply', 'rocklist_rank', 'new_post'
    let message: String
    let createdAt: Date
    let readAt: Date?
    let actor: UserSummary?
    let postId: String?
    let rocklistId: String?
    let oldRank: Int?
    let newRank: Int?
    
    init(
        id: String,
        type: String,
        message: String,
        createdAt: Date,
        readAt: Date? = nil,
        actor: UserSummary? = nil,
        postId: String? = nil,
        rocklistId: String? = nil,
        oldRank: Int? = nil,
        newRank: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.createdAt = createdAt
        self.readAt = readAt
        self.actor = actor
        self.postId = postId
        self.rocklistId = rocklistId
        self.oldRank = oldRank
        self.newRank = newRank
    }
}

