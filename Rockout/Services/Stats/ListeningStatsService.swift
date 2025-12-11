import Foundation
import Combine

/// Service for calculating accurate listening statistics from play history
@MainActor
final class ListeningStatsService: ObservableObject {
    static let shared = ListeningStatsService()
    
    private let spotifyAPI = SpotifyAPI()
    private let appleMusicAPI = AppleMusicAPI.shared
    private let connectionService = MusicPlatformConnectionService.shared
    
    // Cache for play history to avoid repeated API calls
    private var cachedPlayHistory: [PlayHistoryItem] = []
    private var lastCacheUpdate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Play History Model
    
    struct PlayHistoryItem: Identifiable {
        let id: String
        let trackId: String
        let trackName: String
        let artistIds: [String]
        let artistNames: [String]
        let durationMs: Int
        let playedAt: Date
        let platform: MusicPlatform
    }
    
    // MARK: - Fetch Play History
    
    /// Fetches play history from the connected music platform
    /// - Parameters:
    ///   - limit: Maximum number of tracks to fetch per request
    ///   - daysBack: How many days of history to fetch (nil = all available)
    /// - Returns: Array of play history items sorted by most recent first
    func fetchPlayHistory(limit: Int = 200, daysBack: Int? = nil) async throws -> [PlayHistoryItem] {
        // Check cache validity
        if let lastUpdate = lastCacheUpdate,
           Date().timeIntervalSince(lastUpdate) < cacheValidityDuration,
           !cachedPlayHistory.isEmpty {
            print("📊 Using cached play history (\(cachedPlayHistory.count) items)")
            return filterByDaysBack(cachedPlayHistory, daysBack: daysBack)
        }
        
        let connection = try await connectionService.getConnection()
        guard let connection = connection else {
            throw NSError(domain: "ListeningStatsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No music platform connection found"])
        }
        
        var allHistoryItems: [PlayHistoryItem] = []
        let cutoffDate: Date? = daysBack.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
        
        if connection.platform == "spotify" {
            allHistoryItems = try await fetchSpotifyPlayHistory(limit: limit, cutoffDate: cutoffDate)
        } else if connection.platform == "apple_music" {
            allHistoryItems = try await fetchAppleMusicPlayHistory(limit: limit, cutoffDate: cutoffDate)
        }
        
        // Sort by most recent first
        allHistoryItems.sort { $0.playedAt > $1.playedAt }
        
        // Update cache
        cachedPlayHistory = allHistoryItems
        lastCacheUpdate = Date()
        
        return filterByDaysBack(allHistoryItems, daysBack: daysBack)
    }
    
    private func fetchSpotifyPlayHistory(limit: Int, cutoffDate: Date?) async throws -> [PlayHistoryItem] {
        var allItems: [PlayHistoryItem] = []
        var after: Date? = nil
        let maxRequests = min(limit / 50, 10) // Spotify allows 50 per request, fetch up to 500 tracks
        var requestsMade = 0
        
        while requestsMade < maxRequests && allItems.count < limit {
            let response = try await spotifyAPI.getRecentlyPlayed(limit: 50, after: after)
            
            let items = response.items.compactMap { history -> PlayHistoryItem? in
                guard let playedAt = history.playedAt else { return nil }
                
                // Stop if we've hit the cutoff date
                if let cutoff = cutoffDate, playedAt < cutoff {
                    return nil
                }
                
                let artistIds = history.track.artists.map { $0.id }
                let artistNames = history.track.artists.map { $0.name }
                
                return PlayHistoryItem(
                    id: "\(history.track.id)-\(playedAt.timeIntervalSince1970)",
                    trackId: history.track.id,
                    trackName: history.track.name,
                    artistIds: artistIds,
                    artistNames: artistNames,
                    durationMs: history.track.durationMs,
                    playedAt: playedAt,
                    platform: .spotify
                )
            }
            
            if items.isEmpty {
                break
            }
            
            allItems.append(contentsOf: items)
            
            // Set after to the oldest item's playedAt for pagination
            if let oldestItem = items.min(by: { $0.playedAt < $1.playedAt }) {
                after = oldestItem.playedAt
            }
            
            requestsMade += 1
            
            // If we got fewer than 50, we've reached the end
            if items.count < 50 {
                break
            }
        }
        
        print("✅ Fetched \(allItems.count) Spotify play history items")
        return allItems
    }
    
    private func fetchAppleMusicPlayHistory(limit: Int, cutoffDate: Date?) async throws -> [PlayHistoryItem] {
        var allItems: [PlayHistoryItem] = []
        let fetchLimit = min(limit, 200) // Apple Music API limit
        
        let response = try await appleMusicAPI.getRecentlyPlayed(limit: fetchLimit)
        
        let items = response.items.compactMap { history -> PlayHistoryItem? in
            guard let playedAt = history.playedAt else { return nil }
            
            // Stop if we've hit the cutoff date
            if let cutoff = cutoffDate, playedAt < cutoff {
                return nil
            }
            
            let artistIds = history.track.artists.map { $0.id }
            let artistNames = history.track.artists.map { $0.name }
            
            return PlayHistoryItem(
                id: "\(history.track.id)-\(playedAt.timeIntervalSince1970)",
                trackId: history.track.id,
                trackName: history.track.name,
                artistIds: artistIds,
                artistNames: artistNames,
                durationMs: history.track.durationMs,
                playedAt: playedAt,
                platform: .appleMusic
            )
        }
        
        allItems.append(contentsOf: items)
        print("✅ Fetched \(allItems.count) Apple Music play history items")
        return allItems
    }
    
    private func filterByDaysBack(_ items: [PlayHistoryItem], daysBack: Int?) -> [PlayHistoryItem] {
        guard let daysBack = daysBack else { return items }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())
        guard let cutoffDate = cutoffDate else { return items }
        return items.filter { $0.playedAt >= cutoffDate }
    }
    
    // MARK: - Calculate Stats
    
    /// Calculates comprehensive listening statistics from play history
    /// - Parameters:
    ///   - history: Filtered play history items for the selected time range
    ///   - daysBack: Optional number of days back for the time range (nil = all time)
    ///   - allHistory: Optional unfiltered history for discovery comparisons (if nil, uses history)
    func calculateStats(history: [PlayHistoryItem], daysBack: Int? = nil, allHistory: [PlayHistoryItem]? = nil) -> ListeningStats {
        guard !history.isEmpty else {
            return ListeningStats(
                totalListeningTimeMinutes: 0,
                currentStreak: 0,
                longestStreak: 0,
                mostActiveDay: "None",
                mostActiveHour: 0,
                songsDiscoveredThisMonth: 0,
                artistsDiscoveredThisMonth: 0,
                totalSongsPlayed: 0,
                totalArtistsListened: 0
            )
        }
        
        // Total listening time
        let totalListeningTimeMinutes = calculateTotalListeningTime(history: history)
        
        // Streaks
        let (currentStreak, longestStreak) = calculateStreaks(history: history)
        
        // Active times
        let (mostActiveDay, mostActiveHour) = calculateActiveTimes(history: history)
        
        // Discovery metrics - use allHistory for comparison if available (for filtered ranges)
        let comparisonHistory = allHistory ?? history
        let (songsDiscovered, artistsDiscovered) = calculateDiscoveryMetrics(
            history: history,
            daysBack: daysBack,
            allHistoryForComparison: comparisonHistory
        )
        
        // Totals
        let uniqueSongs = Set(history.map { $0.trackId }).count
        let uniqueArtists = Set(history.flatMap { $0.artistIds }).count
        
        print("📊 Stats calculated for \(daysBack.map { "\($0)" } ?? "all time") days:")
        print("   - Total listening time: \(totalListeningTimeMinutes) minutes")
        print("   - Unique songs: \(uniqueSongs)")
        print("   - Unique artists: \(uniqueArtists)")
        print("   - Discoveries: \(songsDiscovered) songs, \(artistsDiscovered) artists")
        
        return ListeningStats(
            totalListeningTimeMinutes: totalListeningTimeMinutes,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            mostActiveDay: mostActiveDay,
            mostActiveHour: mostActiveHour,
            songsDiscoveredThisMonth: songsDiscovered,
            artistsDiscoveredThisMonth: artistsDiscovered,
            totalSongsPlayed: uniqueSongs,
            totalArtistsListened: uniqueArtists
        )
    }
    
    // MARK: - Helper Calculations
    
    private func calculateTotalListeningTime(history: [PlayHistoryItem]) -> Int {
        let totalMs = history.reduce(0) { $0 + $1.durationMs }
        return totalMs / 60000 // Convert to minutes
    }
    
    private func calculateStreaks(history: [PlayHistoryItem]) -> (current: Int, longest: Int) {
        guard !history.isEmpty else { return (0, 0) }
        
        // Group plays by day
        let calendar = Calendar.current
        var daysWithPlays = Set<Date>()
        
        for item in history {
            let day = calendar.startOfDay(for: item.playedAt)
            daysWithPlays.insert(day)
        }
        
        let sortedDays = daysWithPlays.sorted(by: >) // Most recent first
        guard !sortedDays.isEmpty else { return (0, 0) }
        
        // Calculate current streak
        var currentStreak = 0
        let today = calendar.startOfDay(for: Date())
        var expectedDate = today
        
        for day in sortedDays {
            if calendar.isDate(day, inSameDayAs: expectedDate) {
                currentStreak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
            } else {
                // Check if yesterday (allow one day gap for streak continuation)
                let yesterday = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
                if calendar.isDate(day, inSameDayAs: yesterday) {
                    // Continue streak but adjust expected date
                    currentStreak += 1
                    expectedDate = yesterday
                    expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
                } else {
                    break
                }
            }
        }
        
        // Calculate longest streak
        var longestStreak = 1
        var currentSequence = 1
        
        for i in 1..<sortedDays.count {
            let previousDay = sortedDays[i - 1]
            let currentDay = sortedDays[i]
            
            if let daysBetween = calendar.dateComponents([.day], from: currentDay, to: previousDay).day,
               daysBetween == 1 {
                // Consecutive days
                currentSequence += 1
                longestStreak = max(longestStreak, currentSequence)
            } else {
                // Gap in streak
                currentSequence = 1
            }
        }
        
        return (currentStreak, longestStreak)
    }
    
    private func calculateActiveTimes(history: [PlayHistoryItem]) -> (day: String, hour: Int) {
        guard !history.isEmpty else { return ("None", 0) }
        
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE" // Full weekday name
        
        // Count plays by day of week
        var dayCounts: [String: Int] = [:]
        var hourCounts: [Int: Int] = [:]
        
        for item in history {
            // Day of week
            let dayName = dateFormatter.string(from: item.playedAt)
            dayCounts[dayName, default: 0] += 1
            
            // Hour of day
            let hour = calendar.component(.hour, from: item.playedAt)
            hourCounts[hour, default: 0] += 1
        }
        
        // Find most active day
        let mostActiveDay = dayCounts.max(by: { $0.value < $1.value })?.key ?? "None"
        
        // Find most active hour
        let mostActiveHour = hourCounts.max(by: { $0.value < $1.value })?.key ?? 0
        
        return (mostActiveDay, mostActiveHour)
    }
    
    private func calculateDiscoveryMetrics(
        history: [PlayHistoryItem],
        daysBack: Int?,
        allHistoryForComparison: [PlayHistoryItem]
    ) -> (songs: Int, artists: Int) {
        guard !history.isEmpty else { return (0, 0) }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Determine the start date for the time range
        let rangeStart: Date
        if let daysBack = daysBack {
            // For filtered ranges, use the start of that range
            rangeStart = calendar.date(byAdding: .day, value: -daysBack, to: now) ?? now
        } else {
            // For "All Time", use current month start (default behavior)
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
                return (0, 0)
            }
            rangeStart = monthStart
        }
        
        // Filter history to the selected time range
        let rangeHistory = history.filter { $0.playedAt >= rangeStart }
        
        // Sort by playedAt to find first occurrence of each track/artist
        let sortedHistory = rangeHistory.sorted { $0.playedAt < $1.playedAt }
        
        var firstSeenTracks: Set<String> = []
        var firstSeenArtists: Set<String> = []
        
        // Check against history BEFORE the selected range to determine if it's a discovery
        let previousHistory = allHistoryForComparison.filter { $0.playedAt < rangeStart }
        let previousTracks = Set(previousHistory.map { $0.trackId })
        let previousArtists = Set(previousHistory.flatMap { $0.artistIds })
        
        for item in sortedHistory {
            // Track discovery - first time seeing this track in the range, and not seen before
            if !previousTracks.contains(item.trackId) && !firstSeenTracks.contains(item.trackId) {
                firstSeenTracks.insert(item.trackId)
            }
            
            // Artist discovery - first time seeing this artist in the range, and not seen before
            for artistId in item.artistIds {
                if !previousArtists.contains(artistId) && !firstSeenArtists.contains(artistId) {
                    firstSeenArtists.insert(artistId)
                }
            }
        }
        
        print("📊 Discovery metrics for \(daysBack.map { "\($0)" } ?? "all time") days:")
        print("   - Range start: \(rangeStart)")
        print("   - Items in range: \(rangeHistory.count)")
        print("   - Previous items for comparison: \(previousHistory.count)")
        print("   - New songs: \(firstSeenTracks.count)")
        print("   - New artists: \(firstSeenArtists.count)")
        
        return (firstSeenTracks.count, firstSeenArtists.count)
    }
    
    // MARK: - Audio Features Calculation
    
    /// Calculates average audio features from tracks
    /// - Parameters:
    ///   - trackIds: Array of track IDs
    ///   - platform: Music platform (Spotify or Apple Music)
    /// - Returns: AverageAudioFeatures with calculated averages
    func calculateAudioFeatures(trackIds: [String], platform: MusicPlatform) async throws -> AverageAudioFeatures {
        guard !trackIds.isEmpty else {
            // Return default/neutral values if no tracks
            return AverageAudioFeatures(
                danceability: 0.5, energy: 0.5, valence: 0.5, tempo: 120,
                acousticness: 0.5, instrumentalness: 0.5, liveness: 0.5, speechiness: 0.5
            )
        }
        
        // Only Spotify has audio features API
        if platform == .spotify {
            // Fetch audio features for Spotify tracks
            let features = try await spotifyAPI.getAudioFeatures(trackIds: trackIds)
            return averageAudioFeatures(from: features)
        } else {
            // For Apple Music, we can't get audio features directly
            // Return default values or try to match with Spotify via ISRC
            // For now, return neutral values
            print("⚠️ Audio features not available for Apple Music tracks")
            return AverageAudioFeatures(
                danceability: 0.5, energy: 0.5, valence: 0.5, tempo: 120,
                acousticness: 0.5, instrumentalness: 0.5, liveness: 0.5, speechiness: 0.5
            )
        }
    }
    
    private func averageAudioFeatures(from features: [AudioFeatures]) -> AverageAudioFeatures {
        guard !features.isEmpty else {
            return AverageAudioFeatures(
                danceability: 0.5, energy: 0.5, valence: 0.5, tempo: 120,
                acousticness: 0.5, instrumentalness: 0.5, liveness: 0.5, speechiness: 0.5
            )
        }
        
        // Calculate averages, filtering out nil values
        let validDanceability = features.compactMap { $0.danceability }
        let validEnergy = features.compactMap { $0.energy }
        let validValence = features.compactMap { $0.valence }
        let validTempo = features.compactMap { $0.tempo }
        let validAcousticness = features.compactMap { $0.acousticness }
        let validInstrumentalness = features.compactMap { $0.instrumentalness }
        let validLiveness = features.compactMap { $0.liveness }
        let validSpeechiness = features.compactMap { $0.speechiness }
        
        return AverageAudioFeatures(
            danceability: validDanceability.isEmpty ? 0.5 : validDanceability.reduce(0, +) / Double(validDanceability.count),
            energy: validEnergy.isEmpty ? 0.5 : validEnergy.reduce(0, +) / Double(validEnergy.count),
            valence: validValence.isEmpty ? 0.5 : validValence.reduce(0, +) / Double(validValence.count),
            tempo: validTempo.isEmpty ? 120 : validTempo.reduce(0, +) / Double(validTempo.count),
            acousticness: validAcousticness.isEmpty ? 0.5 : validAcousticness.reduce(0, +) / Double(validAcousticness.count),
            instrumentalness: validInstrumentalness.isEmpty ? 0.5 : validInstrumentalness.reduce(0, +) / Double(validInstrumentalness.count),
            liveness: validLiveness.isEmpty ? 0.5 : validLiveness.reduce(0, +) / Double(validLiveness.count),
            speechiness: validSpeechiness.isEmpty ? 0.5 : validSpeechiness.reduce(0, +) / Double(validSpeechiness.count)
        )
    }
    
    // MARK: - Clear Cache
    
    func clearCache() {
        cachedPlayHistory = []
        lastCacheUpdate = nil
    }
}

