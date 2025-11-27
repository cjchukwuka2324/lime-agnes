import Foundation

// MARK: - Common image type
struct SpotifyImage: Codable {
    let url: String
    let width: Int?
    let height: Int?
}

// MARK: - User Profile
struct SpotifyUserProfile: Codable, Identifiable {
    let id: String
    let display_name: String?
    let email: String?
    let country: String?
    let product: String?
    let images: [SpotifyImage]?

    var imageURL: URL? {
        guard let url = images?.first?.url else { return nil }
        return URL(string: url)
    }
    
    // Alias for compatibility
    var displayName: String? { display_name }
}

// MARK: - Artist
struct SpotifyArtist: Codable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]?
    let genres: [String]?       // <-- MUST be optional
    let popularity: Int?

    var imageURL: URL? {
        guard let url = images?.first?.url else { return nil }
        return URL(string: url)
    }
}

// MARK: - Album
struct SpotifyAlbum: Codable, Identifiable {
    let id: String
    let name: String
    let images: [SpotifyImage]?

    var imageURL: URL? {
        guard let url = images?.first?.url else { return nil }
        return URL(string: url)
    }
}

// MARK: - Track
struct SpotifyTrack: Codable, Identifiable {
    let id: String
    let name: String
    let album: SpotifyAlbum?    // <-- MUST be optional
    let artists: [SpotifyArtist]
    let popularity: Int?
    let duration_ms: Int?
    
    var durationMs: Int {
        duration_ms ?? 0
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, album, artists, popularity
        case duration_ms
    }
}

// MARK: - Paging Types
struct SpotifyPaging<T: Codable>: Codable {
    let items: [T]
    let limit: Int
    let offset: Int
    let total: Int
    let next: String?
    let previous: String?
}

struct SpotifyCursorPaging<T: Codable>: Codable {
    let items: [T]
    let next: String?
    let cursors: SpotifyCursors?
    let limit: Int
}

struct SpotifyCursors: Codable {
    let after: String?
    let before: String?
}

// MARK: - Top endpoints
struct SpotifyTopArtistsResponse: Codable {
    let items: [SpotifyArtist]
    let total: Int?
    let limit: Int?
    let offset: Int?
}

struct SpotifyTopTracksResponse: Codable {
    let items: [SpotifyTrack]
    let total: Int?
    let limit: Int?
    let offset: Int?
}

// MARK: - Recently Played
struct SpotifyPlayHistory: Codable {
    let track: SpotifyTrack
    let played_at: String
    
    var playedAt: Date? {
        // Spotify returns ISO8601 format: "2024-01-15T10:30:00.000Z"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: played_at)
    }
    
    enum CodingKeys: String, CodingKey {
        case track
        case played_at
    }
}

struct SpotifyRecentlyPlayedResponse: Codable {
    let items: [SpotifyPlayHistory]
    let next: String?
    let cursors: SpotifyCursors?
}

// MARK: - Following
struct SpotifyFollowingArtistsResponse: Codable {
    let artists: SpotifyCursorPaging<SpotifyArtist>
}

// MARK: - Audio Features
struct SpotifyAudioFeatures: Codable, Identifiable {
    let id: String
    let danceability: Double
    let energy: Double
    let tempo: Double
    let valence: Double?
    let acousticness: Double?
    let instrumentalness: Double?
    let liveness: Double?
    let speechiness: Double?
}

// MARK: - Recommendations

struct SpotifyRecommendationsResponse: Codable {
    let tracks: [SpotifyTrack]
}
