import Foundation

// Import unified models
// Note: UnifiedArtist, UnifiedTrack, etc. are defined in MusicPlatformModels.swift

// MARK: - Stats Time Range
enum StatsTimeRange: String, CaseIterable {
    case last7Days = "last7Days"
    case last30Days = "last30Days"
    case last90Days = "last90Days"
    case last6Months = "last6Months"
    case lastYear = "lastYear"
    case allTime = "allTime"
    
    var displayName: String {
        switch self {
        case .last7Days:
            return "Last 7 Days"
        case .last30Days:
            return "Last 30 Days"
        case .last90Days:
            return "Last 90 Days"
        case .last6Months:
            return "Last 6 Months"
        case .lastYear:
            return "Last Year"
        case .allTime:
            return "All Time"
        }
    }
    
    var daysBack: Int? {
        switch self {
        case .last7Days:
            return 7
        case .last30Days:
            return 30
        case .last90Days:
            return 90
        case .last6Months:
            return 180
        case .lastYear:
            return 365
        case .allTime:
            return nil
        }
    }
}

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
// Note: AudioFeatures is defined in MusicPlatformModels.swift for unified use

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
    let artist: UnifiedArtist
    let discoveredDate: Date
    let playCount: Int
}

// Note: DiscoverWeekly, ReleaseRadar, MoodPlaylist now use UnifiedTrack to support both platforms

struct DiscoverWeekly: Codable {
    let tracks: [UnifiedTrack]
    let updatedAt: Date
    let playlistId: String?
}

struct ReleaseRadar: Codable {
    let tracks: [UnifiedTrack]
    let updatedAt: Date
    let playlistId: String?
}

// MARK: - Mood & Context
struct MoodPlaylist: Codable {
    let mood: String
    let tracks: [UnifiedTrack]
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

