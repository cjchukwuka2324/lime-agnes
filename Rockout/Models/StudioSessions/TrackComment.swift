import Foundation

struct TrackComment: Codable, Identifiable {
    let id: UUID
    let trackId: UUID
    let userId: UUID
    let displayName: String
    let content: String
    let timestamp: Double // Position in seconds
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case trackId = "track_id"
        case userId = "user_id"
        case displayName = "display_name"
        case content
        case timestamp
        case createdAt = "created_at"
    }
    
    // Public initializer for manual creation
    init(id: UUID, trackId: UUID, userId: UUID, displayName: String, content: String, timestamp: Double, createdAt: Date) {
        self.id = id
        self.trackId = trackId
        self.userId = userId
        self.displayName = displayName
        self.content = content
        self.timestamp = timestamp
        self.createdAt = createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        trackId = try container.decode(UUID.self, forKey: .trackId)
        userId = try container.decode(UUID.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Double.self, forKey: .timestamp)
        
        let dateString = try container.decode(String.self, forKey: .createdAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        createdAt = formatter.date(from: dateString) ?? Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(trackId, forKey: .trackId)
        try container.encode(userId, forKey: .userId)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: createdAt), forKey: .createdAt)
    }
}
