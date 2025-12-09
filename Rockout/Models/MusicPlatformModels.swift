import Foundation

// MARK: - Music Platform Enum

enum MusicPlatform: String, Codable {
    case spotify
    case appleMusic
}

// MARK: - Unified Audio Features

struct AudioFeatures: Codable {
    let danceability: Double?
    let energy: Double?
    let valence: Double?
    let tempo: Double?
    let acousticness: Double?
    let instrumentalness: Double?
    let liveness: Double?
    let speechiness: Double?
    
    init(
        danceability: Double? = nil,
        energy: Double? = nil,
        valence: Double? = nil,
        tempo: Double? = nil,
        acousticness: Double? = nil,
        instrumentalness: Double? = nil,
        liveness: Double? = nil,
        speechiness: Double? = nil
    ) {
        self.danceability = danceability
        self.energy = energy
        self.valence = valence
        self.tempo = tempo
        self.acousticness = acousticness
        self.instrumentalness = instrumentalness
        self.liveness = liveness
        self.speechiness = speechiness
    }
}

// MARK: - Unified Album

struct UnifiedAlbum: Codable, Identifiable {
    let id: String
    let name: String
    let imageURL: String?
}

// MARK: - Unified Artist

struct UnifiedArtist: Codable, Identifiable {
    let id: String
    let name: String
    let genres: [String]
    let popularity: Int?
    let imageURL: String?
    let platform: MusicPlatform
}

// MARK: - Unified Track

struct UnifiedTrack: Codable, Identifiable {
    let id: String
    let name: String
    let artists: [UnifiedArtist]
    let album: UnifiedAlbum?
    let durationMs: Int
    let previewURL: String?
    let audioFeatures: AudioFeatures?
    let platform: MusicPlatform
    let isrc: String? // For cross-platform matching
}

// MARK: - Unified User Profile

struct UnifiedUserProfile: Codable, Identifiable {
    let id: String
    let displayName: String?
    let email: String?
    let imageURL: String?
    let platform: MusicPlatform
    
    var imageURLAsURL: URL? {
        guard let imageURL = imageURL else { return nil }
        return URL(string: imageURL)
    }
}

// MARK: - Unified Playlist

struct UnifiedPlaylist: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let tracks: [UnifiedTrack]
    let platform: MusicPlatform
}

// MARK: - Conversion Extensions: Spotify → Unified

extension SpotifyArtist {
    func toUnified() -> UnifiedArtist {
        UnifiedArtist(
            id: self.id,
            name: self.name,
            genres: self.genres ?? [],
            popularity: self.popularity,
            imageURL: self.imageURL?.absoluteString,
            platform: .spotify
        )
    }
}

extension SpotifyTrack {
    func toUnified() -> UnifiedTrack {
        UnifiedTrack(
            id: self.id,
            name: self.name,
            artists: self.artists.map { $0.toUnified() },
            album: self.album.map { UnifiedAlbum(
                id: $0.id,
                name: $0.name,
                imageURL: $0.imageURL?.absoluteString
            ) },
            durationMs: self.durationMs,
            previewURL: self.previewURL?.absoluteString,
            audioFeatures: nil, // Spotify audio features loaded separately
            platform: .spotify,
            isrc: nil
        )
    }
}

extension SpotifyUserProfile {
    func toUnified() -> UnifiedUserProfile {
        UnifiedUserProfile(
            id: self.id,
            displayName: self.display_name,
            email: self.email,
            imageURL: self.imageURL?.absoluteString,
            platform: .spotify
        )
    }
}

// MARK: - Conversion Extensions: Apple Music → Unified

extension AppleMusicArtist {
    func toUnified(platform: MusicPlatform = .appleMusic, popularity: Int? = nil) -> UnifiedArtist {
        UnifiedArtist(
            id: self.id,
            name: self.name,
            genres: self.genres ?? [],
            popularity: popularity ?? self.popularity,
            imageURL: self.imageURL,
            platform: platform
        )
    }
}

extension AppleMusicWebAPIArtist {
    func toAppleMusicArtist() -> AppleMusicArtist {
        AppleMusicArtist(from: self)
    }
}

extension AppleMusicTrack {
    func toUnified(platform: MusicPlatform = .appleMusic, audioFeatures: AudioFeatures? = nil) -> UnifiedTrack {
        UnifiedTrack(
            id: self.id,
            name: self.name,
            artists: self.artists.map { $0.toUnified(platform: platform) },
            album: self.album.map { UnifiedAlbum(
                id: $0.id,
                name: $0.name,
                imageURL: $0.imageURL
            ) },
            durationMs: self.durationMs,
            previewURL: self.previewURL,
            audioFeatures: audioFeatures,
            platform: platform,
            isrc: self.isrc
        )
    }
}

extension AppleMusicWebAPISong {
    func toAppleMusicTrack() -> AppleMusicTrack {
        AppleMusicTrack(from: self)
    }
}

extension AppleMusicUserProfile {
    func toUnified() -> UnifiedUserProfile {
        UnifiedUserProfile(
            id: self.id,
            displayName: self.displayName,
            email: self.email,
            imageURL: nil, // Apple Music user profiles don't typically have image URLs
            platform: .appleMusic
        )
    }
}

