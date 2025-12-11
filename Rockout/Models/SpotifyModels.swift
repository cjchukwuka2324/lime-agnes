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
    let release_date: String?
    let release_date_precision: String? // "year", "month", "day"
    let album_type: String? // "album", "single", "compilation"

    var imageURL: URL? {
        guard let url = images?.first?.url else { return nil }
        return URL(string: url)
    }
    
    var releaseDate: Date? {
        guard let release_date = release_date else { return nil }
        let formatter = DateFormatter()
        if release_date_precision == "day" {
            formatter.dateFormat = "yyyy-MM-dd"
        } else if release_date_precision == "month" {
            formatter.dateFormat = "yyyy-MM"
        } else if release_date_precision == "year" {
            formatter.dateFormat = "yyyy"
        } else {
            // Default to day format
            formatter.dateFormat = "yyyy-MM-dd"
        }
        return formatter.date(from: release_date)
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
    let preview_url: String?
    
    var durationMs: Int {
        duration_ms ?? 0
    }
    
    var previewURL: URL? {
        guard let url = preview_url else { return nil }
        return URL(string: url)
    }
}

// MARK: - Top endpoints
struct SpotifyTopArtistsResponse: Codable {
    let items: [SpotifyArtist]
}

struct SpotifyTopTracksResponse: Codable {
    let items: [SpotifyTrack]
}

// MARK: - Recently Played

struct SpotifyRecentlyPlayedHistoryItem: Codable {
    let track: SpotifyTrack
    let played_at: String?
    
    var playedAt: Date? {
        guard let playedAtString = played_at else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: playedAtString)
    }
}

struct SpotifyRecentlyPlayedResponse: Codable {
    let items: [SpotifyRecentlyPlayedHistoryItem]
}

// MARK: - Followed Artists

struct SpotifyFollowedArtistsResponse: Codable {
    let artists: SpotifyCursorBasedPage<SpotifyArtist>
}

struct SpotifyCursorBasedPage<T: Codable>: Codable {
    let items: [T]
    let next: String?
    let cursors: SpotifyCursor?
    
    struct SpotifyCursor: Codable {
        let after: String?
    }
}

// MARK: - Playlist

struct SpotifyPlaylist: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let images: [SpotifyImage]?
    let owner: SpotifyPlaylistOwner?
    let tracks: SpotifyPlaylistTracks?
    
    var imageURL: URL? {
        guard let url = images?.first?.url else { return nil }
        return URL(string: url)
    }
    
    struct SpotifyPlaylistOwner: Codable {
        let display_name: String?
        let id: String
    }
    
    struct SpotifyPlaylistTracks: Codable {
        let total: Int
    }
}

// MARK: - Playlist Responses

struct SpotifyPlaylistsResponse: Codable {
    let items: [SpotifyPlaylist]
    let next: String?
}

struct SpotifyPlaylistTracksResponse: Codable {
    let items: [SpotifyPlaylistTrackItem]
    let next: String?
    
    struct SpotifyPlaylistTrackItem: Codable {
        let track: SpotifyTrack?
    }
}

// MARK: - Search Results

struct SpotifySearchResponse: Codable {
    let tracks: SpotifySearchTracks?
    let playlists: SpotifySearchPlaylists?
    
    struct SpotifySearchTracks: Codable {
        let items: [SpotifyTrack]
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Handle case where items array might contain null values
            // Spotify API can return null items in arrays, so we need to filter them out
            var itemsContainer = try container.nestedUnkeyedContainer(forKey: .items)
            var decodedItems: [SpotifyTrack] = []
            
            while !itemsContainer.isAtEnd {
                // Try to decode each item, skipping null values
                if let track = try? itemsContainer.decode(SpotifyTrack.self) {
                    decodedItems.append(track)
                } else {
                    // If decoding fails, try to skip the null value
                    _ = try? itemsContainer.decodeNil()
                }
            }
            
            items = decodedItems
        }
        
        enum CodingKeys: String, CodingKey {
            case items
        }
    }
    
    struct SpotifySearchPlaylists: Codable {
        let items: [SpotifyPlaylist]
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Handle case where items array might contain null values
            // Spotify API can return null items in arrays, so we need to filter them out
            var itemsContainer = try container.nestedUnkeyedContainer(forKey: .items)
            var decodedItems: [SpotifyPlaylist] = []
            
            while !itemsContainer.isAtEnd {
                // Try to decode each item, skipping null values
                if let playlist = try? itemsContainer.decode(SpotifyPlaylist.self) {
                    decodedItems.append(playlist)
                } else {
                    // If decoding fails, try to skip the null value
                    _ = try? itemsContainer.decodeNil()
                }
            }
            
            items = decodedItems
        }
        
        enum CodingKeys: String, CodingKey {
            case items
        }
    }
}

// MARK: - Recommendations

struct SpotifyRecommendationsResponse: Codable {
    let tracks: [SpotifyTrack]
}

