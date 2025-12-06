import Foundation

struct ShareableLink: Codable, Identifiable {
    let id: UUID
    let resource_type: String // "album" or "track"
    let resource_id: UUID
    let share_token: String // Unique token for the share link
    let created_by: UUID
    let created_at: String
    var password: String? // Optional password protection
    var expires_at: String? // Optional expiration
    var access_count: Int
    var is_active: Bool
    var is_collaboration: Bool? // Whether this is a collaboration link
}

struct ListenerRecord: Codable, Identifiable {
    let id: UUID
    let share_link_id: UUID
    let resource_type: String
    let resource_id: UUID
    let listener_id: UUID? // Nullable for anonymous listeners
    let listened_at: String
    let duration_listened: Double? // How long they listened
}

struct ShareableLinkDTO: Encodable {
    let resource_type: String
    let resource_id: String
    let share_token: String
    let created_by: String
    let password: String?
    let expires_at: String?
}

struct ListenerDTO: Encodable {
    let share_link_id: String
    let resource_type: String
    let resource_id: String
    let listener_id: String?
    let duration_listened: Double?
}

