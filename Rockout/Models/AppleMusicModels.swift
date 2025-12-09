import Foundation
import MusicKit

// MARK: - Apple Music Models
// These models wrap MusicKit types for use in our app

struct AppleMusicUserProfile: Codable, Identifiable {
    let id: String
    let displayName: String?
    let email: String?
    
    // Manual initializer (MusicKit doesn't provide direct user profile access)
    init(id: String, displayName: String? = nil, email: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.email = email
    }
}

struct AppleMusicArtist: Codable, Identifiable {
    let id: String
    let name: String
    let imageURL: String?
    let genres: [String]? // From Web API
    let popularity: Int? // From Web API (not directly available, but can be derived)
    
    // Initialize from MusicKit Artist
    init(from artist: Artist) {
        self.id = artist.id.rawValue
        self.name = artist.name
        self.imageURL = artist.artwork?.url(width: 300, height: 300)?.absoluteString
        self.genres = nil
        self.popularity = nil
    }
    
    // Initialize from Web API Artist
    init(from webAPIArtist: AppleMusicWebAPIArtist) {
        self.id = webAPIArtist.id
        self.name = webAPIArtist.attributes.name
        self.imageURL = webAPIArtist.attributes.artwork?.urlForSize(width: 300, height: 300)
        self.genres = webAPIArtist.attributes.genreNames
        self.popularity = nil // Web API doesn't provide popularity directly
    }
    
    // Manual initializer for convenience
    init(id: String, name: String, imageURL: String? = nil, genres: [String]? = nil, popularity: Int? = nil) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.genres = genres
        self.popularity = popularity
    }
}

struct AppleMusicTrack: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [AppleMusicArtist]
    let durationMs: Int
    let isrc: String? // ISRC code for cross-platform matching
    let previewURL: String?
    let album: AppleMusicAlbum?
    let genreNames: [String]? // From Web API
    
    // Initialize from MusicKit Song
    init(from song: Song) {
        self.id = song.id.rawValue
        self.name = song.title
        self.artists = song.artistName.split(separator: ",").map { name in
            // Create artist from name (we don't have full Artist object)
            // In production, you'd want to fetch full artist details
            AppleMusicArtist(id: "", name: String(name.trimmingCharacters(in: .whitespaces)), imageURL: nil)
        }
        self.durationMs = Int(song.duration ?? 0) * 1000 // Convert to milliseconds
        self.isrc = song.isrc // ISRC code
        self.previewURL = song.previewAssets?.first?.url?.absoluteString
        self.album = song.albumTitle.map { AppleMusicAlbum(id: "", name: $0, imageURL: nil) }
        self.genreNames = song.genreNames
    }
    
    // Initialize from Web API Song
    init(from webAPISong: AppleMusicWebAPISong) {
        self.id = webAPISong.id
        self.name = webAPISong.attributes.name
        self.artists = [AppleMusicArtist(
            id: "", // Web API doesn't provide artist ID in song attributes
            name: webAPISong.attributes.artistName,
            imageURL: nil
        )]
        self.durationMs = webAPISong.attributes.durationInMillis ?? 0
        self.isrc = webAPISong.attributes.isrc
        self.previewURL = webAPISong.attributes.previews?.first?.url
        self.album = webAPISong.attributes.albumName.map { AppleMusicAlbum(id: "", name: $0, imageURL: webAPISong.attributes.artwork?.urlForSize(width: 300, height: 300)) }
        self.genreNames = webAPISong.attributes.genreNames
    }
    
    // Manual initializer
    init(id: String, name: String, artists: [AppleMusicArtist], durationMs: Int, isrc: String? = nil, previewURL: String? = nil, album: AppleMusicAlbum? = nil, genreNames: [String]? = nil) {
        self.id = id
        self.name = name
        self.artists = artists
        self.durationMs = durationMs
        self.isrc = isrc
        self.previewURL = previewURL
        self.album = album
        self.genreNames = genreNames
    }
}

struct AppleMusicAlbum: Codable, Identifiable {
    let id: String
    let name: String
    let imageURL: String?
    
    // Initialize from MusicKit Album
    init(from album: Album) {
        self.id = album.id.rawValue
        self.name = album.title
        self.imageURL = album.artwork?.url(width: 300, height: 300)?.absoluteString
    }
    
    // Manual initializer for convenience
    init(id: String, name: String, imageURL: String?) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
    }
}

struct AppleMusicPlayHistory: Codable {
    let track: AppleMusicTrack
    let playedAt: Date?
}

struct AppleMusicRecentlyPlayedResponse: Codable {
    let items: [AppleMusicPlayHistory]
}

struct AppleMusicTopArtistsResponse: Codable {
    let items: [AppleMusicArtist]
}

struct AppleMusicTopTracksResponse: Codable {
    let items: [AppleMusicTrack]
}

// MARK: - Apple Music Web API Models

struct AppleMusicWebAPIArtist: Codable, Identifiable {
    let id: String
    let type: String
    let attributes: AppleMusicWebAPIArtistAttributes
    
    enum CodingKeys: String, CodingKey {
        case id, type, attributes
    }
}

struct AppleMusicWebAPIArtistAttributes: Codable {
    let name: String
    let genreNames: [String]?
    let artwork: AppleMusicWebAPIArtwork?
    let url: String?
}

struct AppleMusicWebAPISong: Codable, Identifiable {
    let id: String
    let type: String
    let attributes: AppleMusicWebAPISongAttributes
    
    enum CodingKeys: String, CodingKey {
        case id, type, attributes
    }
}

struct AppleMusicWebAPISongAttributes: Codable {
    let name: String
    let artistName: String
    let albumName: String?
    let durationInMillis: Int?
    let previews: [AppleMusicWebAPIPreview]?
    let artwork: AppleMusicWebAPIArtwork?
    let genreNames: [String]?
    let isrc: String?
    let url: String?
    let playParams: AppleMusicWebAPIPlayParams?
}

struct AppleMusicWebAPIPreview: Codable {
    let url: String
}

struct AppleMusicWebAPIArtwork: Codable {
    let url: String
    let width: Int?
    let height: Int?
    
    func urlForSize(width: Int, height: Int) -> String {
        return url.replacingOccurrences(of: "{w}", with: "\(width)")
                  .replacingOccurrences(of: "{h}", with: "\(height)")
    }
}

struct AppleMusicWebAPIPlayParams: Codable {
    let id: String
}

struct AppleMusicWebAPILibrarySong: Codable {
    let id: String
    let type: String
    let attributes: AppleMusicWebAPISongAttributes
}

struct AppleMusicWebAPIPlayHistory: Codable {
    let id: String
    let type: String
    let attributes: AppleMusicWebAPIPlayHistoryAttributes
}

struct AppleMusicWebAPIPlayHistoryAttributes: Codable {
    let playDate: String
    let song: AppleMusicWebAPISong?
}

struct AppleMusicWebAPISearchResponse: Codable {
    let results: AppleMusicWebAPISearchResults
}

struct AppleMusicWebAPISearchResults: Codable {
    let songs: AppleMusicWebAPISearchData<AppleMusicWebAPISong>?
    let artists: AppleMusicWebAPISearchData<AppleMusicWebAPIArtist>?
}

struct AppleMusicWebAPISearchData<T: Codable>: Codable {
    let data: [T]
}

