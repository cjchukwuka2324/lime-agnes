import Foundation

// MARK: - Listening Stats
struct ListeningStats: Codable {
    let totalListeningTimeMinutes: Int
    let currentStreak: Int
    let longestStreak: Int
    let mostActiveDay: String
    let mostActiveHour: Int
    let songsDiscoveredThisMonth: Int
    let artistsDiscoveredThisMonth: Int
    let totalSongsPlayed: Int
    let totalArtistsListened: Int
}

// MARK: - Audio Features
struct AudioFeatures: Codable {
    let danceability: Double
    let energy: Double
    let valence: Double
    let tempo: Double
    let acousticness: Double
    let instrumentalness: Double
    let liveness: Double
    let speechiness: Double
}

struct AverageAudioFeatures: Codable {
    let danceability: Double
    let energy: Double
    let valence: Double
    let tempo: Double
    let acousticness: Double
    let instrumentalness: Double
    let liveness: Double
    let speechiness: Double
}

// MARK: - Time-Based Analysis
struct MonthlyEvolution: Codable {
    let month: String
    let topGenres: [String]
    let topArtists: [String]
    let listeningTimeMinutes: Int
}

struct YearInMusic: Codable {
    let year: Int
    let totalListeningTimeMinutes: Int
    let topGenres: [String]
    let topArtists: [String]
    let topTracks: [String]
    let favoriteDecade: String
    let mostPlayedMonth: String
}

// MARK: - Discovery Data
struct RecentlyDiscovered: Codable {
    let artist: SpotifyArtist
    let discoveredDate: Date
    let playCount: Int
}

struct DiscoverWeekly: Codable {
    let tracks: [SpotifyTrack]
    let updatedAt: Date
}

struct ReleaseRadar: Codable {
    let tracks: [SpotifyTrack]
    let updatedAt: Date
}

// MARK: - Mood & Context
struct MoodPlaylist: Codable {
    let mood: String
    let tracks: [SpotifyTrack]
    let description: String
}

struct TimePattern: Codable {
    let hour: Int
    let playCount: Int
    let dominantGenre: String
}

struct SeasonalTrend: Codable {
    let season: String
    let topGenres: [String]
    let listeningTimeMinutes: Int
}

// MARK: - Advanced Analytics
struct MusicTasteDiversity: Codable {
    let score: Double // 0-100
    let genreCount: Int
    let artistCount: Int
    let explorationDepth: Double
}

struct TasteCompatibility: Codable {
    let userId: String
    let userName: String
    let compatibilityScore: Double
    let sharedArtists: [String]
    let sharedGenres: [String]
}

