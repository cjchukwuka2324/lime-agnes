import Foundation

// MARK: - RockList Entry

struct RockListEntry: Decodable, Identifiable {
    let artistId: String
    let artistName: String
    let artistImageURL: String?
    let userId: UUID
    let displayName: String
    let score: Double  // Legacy score (kept for backward compatibility)
    let listenerScore: Double?  // New unified Listener Score (0-100)
    let rank: Int
    let isCurrentUser: Bool
    
    var id: UUID { userId }
    
    // Computed property to get the active score (prefer listenerScore, fallback to score)
    var activeScore: Double {
        listenerScore ?? score
    }
    
    enum CodingKeys: String, CodingKey {
        case artistId = "artist_id"
        case artistName = "artist_name"
        case artistImageURL = "artist_image_url"
        case userId = "user_id"
        case displayName = "display_name"
        case score
        case listenerScore = "listener_score"
        case rank
        case isCurrentUser = "is_current_user"
    }
}

// MARK: - RockList Response
// ArtistSummary is now defined in SharedFilters.swift

struct RockListResponse {
    let artist: ArtistSummary
    let top20: [RockListEntry]
    let currentUserEntry: RockListEntry?
}

// MARK: - My RockList Rank

struct MyRockListRank: Decodable, Identifiable {
    let artistId: String
    let artistName: String
    let artistImageURL: String?
    let myRank: Int?
    let myScore: Double?  // Legacy score (kept for backward compatibility)
    let myListenerScore: Double?  // New unified Listener Score (0-100)
    
    var id: String { artistId }
    
    // Computed property to get the active score (prefer listenerScore, fallback to score)
    var activeScore: Double? {
        myListenerScore ?? myScore
    }
    
    enum CodingKeys: String, CodingKey {
        case artistId = "artist_id"
        case artistName = "artist_name"
        case artistImageURL = "artist_image_url"
        case myRank = "my_rank"
        case myScore = "my_score"
        case myListenerScore = "my_listener_score"
    }
}

// MARK: - RockList Comment

struct RockListComment: Decodable, Identifiable {
    let id: UUID
    let userId: UUID
    let displayName: String
    let content: String
    let createdAt: Date
    let artistId: String?
    let studioSessionId: UUID?
    let commentType: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case content
        case createdAt = "created_at"
        case artistId = "artist_id"
        case studioSessionId = "studio_session_id"
        case commentType = "comment_type"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        content = try container.decode(String.self, forKey: .content)
        
        let dateString = try container.decode(String.self, forKey: .createdAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        createdAt = formatter.date(from: dateString) ?? Date()
        
        artistId = try container.decodeIfPresent(String.self, forKey: .artistId)
        studioSessionId = try container.decodeIfPresent(UUID.self, forKey: .studioSessionId)
        commentType = try container.decodeIfPresent(String.self, forKey: .commentType)
    }
}

// MARK: - Feed Item

struct FeedItem: Decodable, Identifiable {
    let commentId: UUID
    let userId: UUID
    let displayName: String
    let content: String
    let createdAt: Date
    let artistId: String?
    let artistName: String?
    let artistImageURL: String?
    let studioSessionId: UUID?
    let commentType: String
    
    var id: UUID { commentId }
    
    enum CodingKeys: String, CodingKey {
        case commentId = "comment_id"
        case userId = "user_id"
        case displayName = "display_name"
        case content
        case createdAt = "created_at"
        case artistId = "artist_id"
        case artistName = "artist_name"
        case artistImageURL = "artist_image_url"
        case studioSessionId = "studio_session_id"
        case commentType = "comment_type"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commentId = try container.decode(UUID.self, forKey: .commentId)
        userId = try container.decode(UUID.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        content = try container.decode(String.self, forKey: .content)
        commentType = try container.decode(String.self, forKey: .commentType)
        
        let dateString = try container.decode(String.self, forKey: .createdAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        createdAt = formatter.date(from: dateString) ?? Date()
        
        artistId = try container.decodeIfPresent(String.self, forKey: .artistId)
        artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
        artistImageURL = try container.decodeIfPresent(String.self, forKey: .artistImageURL)
        studioSessionId = try container.decodeIfPresent(UUID.self, forKey: .studioSessionId)
    }
}

