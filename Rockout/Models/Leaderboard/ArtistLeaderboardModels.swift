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

// MARK: - Artist Summary

struct ArtistSummary: Decodable {
    let id: String
    let name: String
    let imageURL: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "artist_id"
        case name = "artist_name"
        case imageURL = "artist_image_url"
    }
}

// MARK: - Artist Leaderboard Response

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

