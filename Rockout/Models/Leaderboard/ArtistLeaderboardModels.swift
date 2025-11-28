import Foundation

// MARK: - Artist Leaderboard Entry

struct ArtistLeaderboardEntry: Decodable, Identifiable {
    let artistId: String
    let artistName: String
    let artistImageURL: String?
    let userId: UUID
    let displayName: String
    let score: Double
    let rank: Int
    let isCurrentUser: Bool
    
    var id: UUID { userId }
    
    enum CodingKeys: String, CodingKey {
        case artistId = "artist_id"
        case artistName = "artist_name"
        case artistImageURL = "artist_image_url"
        case userId = "user_id"
        case displayName = "display_name"
        case score
        case rank
        case isCurrentUser = "is_current_user"
    }
}

// MARK: - Artist Leaderboard Response
// ArtistSummary is now defined in SharedFilters.swift

struct ArtistLeaderboardResponse {
    let artist: ArtistSummary
    let top20: [ArtistLeaderboardEntry]
    let currentUserEntry: ArtistLeaderboardEntry?
}

// MARK: - My Artist Rank

struct MyArtistRank: Decodable, Identifiable {
    let artistId: String
    let artistName: String
    let artistImageURL: String?
    let myRank: Int?
    let myScore: Double?
    
    var id: String { artistId }
    
    enum CodingKeys: String, CodingKey {
        case artistId = "artist_id"
        case artistName = "artist_name"
        case artistImageURL = "artist_image_url"
        case myRank = "my_rank"
        case myScore = "my_score"
    }
}

