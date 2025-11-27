import Foundation

// MARK: - Listening Personality Enum

enum FanPersonality: String, CaseIterable, Identifiable {
    case mainstreamMaven
    case deepCutDiver
    case genreExplorer
    case loyalRepeater
    case vibeySoul
    case balancedListener

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mainstreamMaven: return "Mainstream Maven"
        case .deepCutDiver:    return "Deep Cut Diver"
        case .genreExplorer:   return "Genre Explorer"
        case .loyalRepeater:   return "Loyal Repeater"
        case .vibeySoul:       return "Vibey Soul"
        case .balancedListener:return "Balanced Listener"
        }
    }

    var emoji: String {
        switch self {
        case .mainstreamMaven: return "📈"
        case .deepCutDiver:    return "🕳️"
        case .genreExplorer:   return "🧭"
        case .loyalRepeater:   return "🔁"
        case .vibeySoul:       return "💫"
        case .balancedListener:return "⚖️"
        }
    }

    var description: String {
        switch self {
        case .mainstreamMaven:
            return "You stay where the charts are. Big artists, big hits, big energy."
        case .deepCutDiver:
            return "You live in the liner notes. You chase B-sides, remixes and hidden gems."
        case .genreExplorer:
            return "You’re everywhere at once. Your queue is a passport through genres."
        case .loyalRepeater:
            return "When you love a song, you REALLY love it. Replay is your love language."
        case .vibeySoul:
            return "You curate mood more than genre. You chase feelings, not labels."
        case .balancedListener:
            return "You dance between hits and deep cuts, structure and chaos. Perfect balance."
        }
    }
}

// MARK: - Personality Engine

struct FanPersonalityEngine {

    static func compute(artists: [SpotifyArtist], tracks: [SpotifyTrack]) -> FanPersonality {
        // Unique genre count (breadth)
        let uniqueGenres = Set(
            artists
                .flatMap { $0.genres ?? [] }   // 👈 handle optional
                .map { $0.lowercased() }
        ).count

        // Average artist popularity (mainstream vs niche)
        let avgPopularity: Double = {
            let scores = artists.compactMap { $0.popularity }
            guard !scores.isEmpty else { return 50 }
            return Double(scores.reduce(0, +)) / Double(scores.count)
        }()

        // Dominance of top genre
        let genreCounts = genreFrequency(from: artists)
        let totalGenreHits = Double(genreCounts.values.reduce(0, +))
        let topShare: Double = {
            guard let maxValue = genreCounts.values.max(), totalGenreHits > 0 else { return 0 }
            return Double(maxValue) / totalGenreHits
        }()

        // Heuristics
        if avgPopularity > 75 && topShare > 0.4 {
            return .mainstreamMaven
        }

        if uniqueGenres > 18 {
            return .genreExplorer
        }

        if topShare > 0.55 && avgPopularity < 60 {
            return .deepCutDiver
        }

        if tracks.count > 15 && topShare > 0.45 {
            return .loyalRepeater
        }

        if containsVibeGenres(genreCounts.keys) {
            return .vibeySoul
        }

        return .balancedListener
    }

    private static func genreFrequency(from artists: [SpotifyArtist]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for artist in artists {
            for g in (artist.genres ?? []) {    // 👈 handle optional
                let key = g.lowercased()
                counts[key, default: 0] += 1
            }
        }
        return counts
    }

    // Accept ANY sequence of String (Dictionary.Keys, Array, Set, etc.)
    private static func containsVibeGenres<S: Sequence>(_ genres: S) -> Bool where S.Element == String {
        for g in genres {
            let lower = g.lowercased()
            if lower.contains("r&b") ||
               lower.contains("rnb") ||
               lower.contains("neo-soul") ||
               lower.contains("afrobeats") ||
               lower.contains("afrobeat") ||
               lower.contains("afro") ||
               lower.contains("chill") {
                return true
            }
        }
        return false
    }
}
