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
    let images: [SpotifyImage]?

    var imageURL: URL? {
        guard let url = images?.first?.url else { return nil }
        return URL(string: url)
    }
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
}

// MARK: - Top endpoints
struct SpotifyTopArtistsResponse: Codable {
    let items: [SpotifyArtist]
}

struct SpotifyTopTracksResponse: Codable {
    let items: [SpotifyTrack]
}

// MARK: - Recommendations

struct SpotifyRecommendationsResponse: Codable {
    let tracks: [SpotifyTrack]
}
