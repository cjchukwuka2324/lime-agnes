import Foundation

// MARK: - Listener Score Breakdown

struct ListenerScoreBreakdown: Decodable {
    let listenerScore: Double
    let streamIndex: ScoreIndex
    let durationIndex: ScoreIndex
    let completionIndex: ScoreIndex
    let recencyIndex: ScoreIndex
    let engagementIndex: ScoreIndex
    let fanSpreadIndex: ScoreIndex
    
    enum CodingKeys: String, CodingKey {
        case listenerScore = "listener_score"
        case streamIndex = "stream_index"
        case durationIndex = "duration_index"
        case completionIndex = "completion_index"
        case recencyIndex = "recency_index"
        case engagementIndex = "engagement_index"
        case fanSpreadIndex = "fan_spread_index"
    }
}

// MARK: - Score Index

struct ScoreIndex: Decodable {
    let value: Double  // Normalized value (0-1)
    let weight: Double  // Weight in formula (0-1)
    let contribution: Double  // Weighted contribution to final score (0-100)
    let raw: RawData
    
    enum CodingKeys: String, CodingKey {
        case value
        case weight
        case contribution
        case raw
    }
}

// MARK: - Raw Data

struct RawData: Decodable {
    // StreamIndex raw data
    let streamCount: Int?
    let maxStreamCount: Int?
    
    // DurationIndex raw data
    let totalMinutes: Double?
    let maxMinutes: Double?
    
    // CompletionIndex raw data
    let avgCompletionRate: Double?
    
    // RecencyIndex raw data
    let daysSinceLastListen: Double?
    
    // EngagementIndex raw data
    let engagementRaw: Int?
    let maxEngagementRaw: Int?
    let albumSaves: Int?
    let trackLikes: Int?
    let playlistAdds: Int?
    
    // FanSpreadIndex raw data
    let uniqueTracks: Int?
    let totalTracks: Int?
    
    enum CodingKeys: String, CodingKey {
        case streamCount = "stream_count"
        case maxStreamCount = "max_stream_count"
        case totalMinutes = "total_minutes"
        case maxMinutes = "max_minutes"
        case avgCompletionRate = "avg_completion_rate"
        case daysSinceLastListen = "days_since_last_listen"
        case engagementRaw = "engagement_raw"
        case maxEngagementRaw = "max_engagement_raw"
        case albumSaves = "album_saves"
        case trackLikes = "track_likes"
        case playlistAdds = "playlist_adds"
        case uniqueTracks = "unique_tracks"
        case totalTracks = "total_tracks"
    }
}





