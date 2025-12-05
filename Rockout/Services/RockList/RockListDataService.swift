import Foundation
import Supabase

/// Service for orchestrating Spotify data access for RockList features.
/// This service normalizes Spotify listening data into formats suitable
/// for RockList ingestion and UI consumption.
@MainActor
final class RockListDataService {
    static let shared = RockListDataService()
    
    private let spotifyAPI = SpotifyAPI()
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    // MARK: - Play Events
    
    /// Represents a normalized play event from Spotify for RockList ingestion
    struct RockListPlayEvent: Codable {
        let artistId: String
        let artistName: String
        let trackId: String
        let trackName: String
        let playedAt: Date
        let durationMs: Int
        let region: String?
        
        enum CodingKeys: String, CodingKey {
            case artistId, artistName, trackId, trackName, playedAt, durationMs, region
        }
        
        // Regular initializer for creating instances in code
        init(
            artistId: String,
            artistName: String,
            trackId: String,
            trackName: String,
            playedAt: Date,
            durationMs: Int,
            region: String?
        ) {
            self.artistId = artistId
            self.artistName = artistName
            self.trackId = trackId
            self.trackName = trackName
            self.playedAt = playedAt
            self.durationMs = durationMs
            self.region = region
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(artistId, forKey: .artistId)
            try container.encode(artistName, forKey: .artistName)
            try container.encode(trackId, forKey: .trackId)
            try container.encode(trackName, forKey: .trackName)
            
            // Encode date as ISO8601 string for JSONB compatibility
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: playedAt), forKey: .playedAt)
            
            try container.encode(durationMs, forKey: .durationMs)
            try container.encodeIfPresent(region, forKey: .region)
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            artistId = try container.decode(String.self, forKey: .artistId)
            artistName = try container.decode(String.self, forKey: .artistName)
            trackId = try container.decode(String.self, forKey: .trackId)
            trackName = try container.decode(String.self, forKey: .trackName)
            
            // Decode date from ISO8601 string
            let dateString = try container.decode(String.self, forKey: .playedAt)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: dateString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .playedAt,
                    in: container,
                    debugDescription: "Invalid date format: \(dateString)"
                )
            }
            playedAt = date
            
            durationMs = try container.decode(Int.self, forKey: .durationMs)
            region = try container.decodeIfPresent(String.self, forKey: .region)
        }
    }
    
    // MARK: - Initial Bootstrap Ingestion
    
    /// Performs initial bootstrap ingestion after Spotify connection
    /// Fetches profile, recently played, and top artists/tracks
    func performInitialBootstrapIngestion() async throws {
        print("🚀 RockListDataService: Starting initial bootstrap ingestion...")
        
        do {
            let profile = try await spotifyAPI.getCurrentUserProfile()
            let region = profile.country ?? "GLOBAL"
            print("👤 User profile: \(profile.display_name ?? "Unknown"), region: \(region)")
            
            var events: [RockListPlayEvent] = []
            
            // 1) Recently played tracks
            print("📻 Fetching recently played tracks...")
            let recent = try await spotifyAPI.getRecentlyPlayed(limit: 50)
            print("📻 Found \(recent.items.count) recently played tracks")
            
            let recentEvents = recent.items.compactMap { history -> RockListPlayEvent? in
                guard let playedAt = history.playedAt,
                      let firstArtist = history.track.artists.first else {
                    return nil
                }
                
                return RockListPlayEvent(
                    artistId: firstArtist.id,
                    artistName: firstArtist.name,
                    trackId: history.track.id,
                    trackName: history.track.name,
                    playedAt: playedAt,
                    durationMs: history.track.durationMs,
                    region: region
                )
            }
            events.append(contentsOf: recentEvents)
            print("✅ Added \(recentEvents.count) recent play events")
            
            // 2) Top artists (long_term) -> add "virtual" events to weight favorites
            print("🎵 Fetching top artists...")
            let topArtists = try await spotifyAPI.getTopArtists(timeRange: .longTerm, limit: 20)
            print("🎵 Found \(topArtists.items.count) top artists")
            
            var virtualEventCount = 0
            for (index, artist) in topArtists.items.enumerated() {
                let weight = max(1, 5 - index / 5) // decreasing weight with rank
                for _ in 0..<weight {
                    events.append(
                        RockListPlayEvent(
                            artistId: artist.id,
                            artistName: artist.name,
                            trackId: "virtual-\(artist.id)-\(index)",
                            trackName: "Virtual play for ranking",
                            playedAt: Date(), // now
                            durationMs: 180_000, // 3 minutes
                            region: region
                        )
                    )
                    virtualEventCount += 1
                }
            }
            print("✅ Added \(virtualEventCount) virtual events from top artists")
            
            // 3) Optionally include top tracks (optional enhancement)
            // This can be added later if needed
            
            print("📊 Total events to ingest: \(events.count)")
            
            // Send events to Supabase for ingestion
            try await sendEventsToBackend(events)
            
            print("✅ RockListDataService: Initial bootstrap ingestion completed successfully")
        } catch {
            print("❌ RockListDataService: Bootstrap ingestion failed: \(error)")
            print("❌ Error: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Incremental Ingestion
    
    /// Performs incremental ingestion using last_ingested_played_at timestamp
    /// - Parameter lastIngestedAt: Last ingestion timestamp from backend (optional)
    func performIncrementalIngestion(lastIngestedAt: Date? = nil) async throws {
        let profile = try await spotifyAPI.getCurrentUserProfile()
        let region = profile.country
        
        // Fetch recently played tracks after the last ingested timestamp
        let recent = try await spotifyAPI.getRecentlyPlayed(
            limit: 50,
            after: lastIngestedAt
        )
        
        let events: [RockListPlayEvent] = recent.items.compactMap { history -> RockListPlayEvent? in
            guard let playedAt = history.playedAt,
                  let firstArtist = history.track.artists.first else {
                return nil
            }
            
            // Only include events that are newer than lastIngestedAt (if provided)
            if let lastIngested = lastIngestedAt, playedAt <= lastIngested {
                return nil
            }
            
            return RockListPlayEvent(
                artistId: firstArtist.id,
                artistName: firstArtist.name,
                trackId: history.track.id,
                trackName: history.track.name,
                playedAt: playedAt,
                durationMs: history.track.durationMs,
                region: region
            )
        }
        
        guard !events.isEmpty else { return }
        
        try await sendEventsToBackend(events)
    }
    
    // MARK: - Backend Communication
    
    /// Encodable struct for RPC parameter
    private struct IngestEvent: Encodable {
        let artistId: String
        let artistName: String
        let trackId: String
        let trackName: String
        let playedAt: String  // ISO8601 string
        let durationMs: Int
        let region: String
    }
    
    /// Sends play events to Supabase for ingestion
    private func sendEventsToBackend(_ events: [RockListPlayEvent]) async throws {
        guard !events.isEmpty else {
            print("⚠️ RockListDataService: No events to send")
            return
        }
        
        print("📤 RockListDataService: Sending \(events.count) events to backend...")
        
        // Convert events to Encodable format for JSONB
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let ingestEvents: [IngestEvent] = events.map { event in
            IngestEvent(
                artistId: event.artistId,
                artistName: event.artistName,
                trackId: event.trackId,
                trackName: event.trackName,
                playedAt: formatter.string(from: event.playedAt),
                durationMs: event.durationMs,
                region: event.region ?? "GLOBAL"
            )
        }
        
        print("📤 RockListDataService: Event sample: \(ingestEvents.first?.artistName ?? "none")")
        
        do {
            // Call Supabase RPC: rocklist_ingest_plays
            // The RPC expects a JSONB parameter, which Supabase Swift client handles automatically
            let response = try await supabase
                .rpc("rocklist_ingest_plays", params: ["p_events": ingestEvents])
                .execute()
            
            print("✅ RockListDataService: Successfully ingested \(events.count) events")
            print("📊 Response: \(String(data: response.data, encoding: .utf8) ?? "no data")")
        } catch {
            print("❌ RockListDataService: Failed to ingest events: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ User info: \(nsError.userInfo)")
            }
            throw error
        }
    }
    
    /// Fetches the last ingested timestamp from backend
    /// - Returns: Last ingested timestamp, or nil if never ingested
    func getLastIngestedTimestamp() async throws -> Date? {
        struct UserStateResponse: Codable {
            let last_ingested_played_at: String?
        }
        
        let response = try await supabase
            .rpc("get_rocklist_user_state")
            .execute()
        
        let states: [UserStateResponse] = try JSONDecoder().decode(
            [UserStateResponse].self,
            from: response.data
        )
        
        guard let state = states.first,
              let timestampString = state.last_ingested_played_at else {
            return nil
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestampString)
    }
    
    /// Checks if user needs initial ingestion and triggers it if needed
    /// This is useful for existing users who connected Spotify before ingestion was added
    func checkAndTriggerInitialIngestionIfNeeded() async {
        // Only check if Spotify is authorized
        guard SpotifyAuthService.shared.isAuthorized() else {
            print("ℹ️ RockListDataService: Spotify not authorized, skipping ingestion check")
            return
        }
        
        do {
            // Check if user has ever ingested data
            let lastIngested = try await getLastIngestedTimestamp()
            
            if lastIngested == nil {
                // User has never ingested - trigger initial bootstrap
                print("🔄 RockListDataService: No previous ingestion found, triggering initial bootstrap...")
                try await performInitialBootstrapIngestion()
                print("✅ RockListDataService: Initial ingestion completed for existing user")
            } else {
                // User has ingested before - do incremental update
                print("🔄 RockListDataService: Previous ingestion found, doing incremental update...")
                try await performIncrementalIngestion(lastIngestedAt: lastIngested)
                print("✅ RockListDataService: Incremental ingestion completed")
            }
        } catch {
            print("⚠️ RockListDataService: Failed to check/trigger ingestion: \(error.localizedDescription)")
            // Don't throw - this is a background operation
        }
    }
    
    // MARK: - Legacy Methods (kept for compatibility)
    
    /// Fetches recent play events from Spotify (legacy method)
    /// - Parameter limit: Maximum number of recent plays to fetch (default: 50, max: 50)
    /// - Returns: Array of normalized play events
    func fetchRecentPlayEvents(limit: Int = 50) async throws -> [RockListPlayEvent] {
        // Fetch user profile to get region
        let userProfile = try await spotifyAPI.getCurrentUserProfile()
        
        // Fetch recently played tracks
        let recentlyPlayed = try await spotifyAPI.getRecentlyPlayed(limit: min(limit, 50))
        
        // Convert to play events
        return recentlyPlayed.items.compactMap { history -> RockListPlayEvent? in
            guard let playedAt = history.playedAt,
                  let firstArtist = history.track.artists.first else {
                return nil
            }
            
            return RockListPlayEvent(
                artistId: firstArtist.id,
                artistName: firstArtist.name,
                trackId: history.track.id,
                trackName: history.track.name,
                playedAt: playedAt,
                durationMs: history.track.durationMs,
                region: userProfile.country
            )
        }
    }
    
    // MARK: - Top Artists for RockList UI
    
    /// Fetches user's top artists for RockList display
    /// - Parameters:
    ///   - timeRange: Time range for top artists (default: .mediumTerm)
    ///   - limit: Number of artists to fetch (default: 20)
    /// - Returns: Array of Spotify artists
    func fetchMyTopArtistsForRockList(
        timeRange: SpotifyAPI.SpotifyTimeRange = .mediumTerm,
        limit: Int = 20
    ) async throws -> [SpotifyArtist] {
        let response = try await spotifyAPI.getTopArtists(
            timeRange: timeRange,
            limit: limit
        )
        return response.items
    }
    
    // MARK: - Followed Artists for RockList UI
    
    /// Fetches artists the user follows for RockList display
    /// - Parameter limit: Maximum number of followed artists to fetch (default: 50)
    /// - Returns: Array of followed Spotify artists
    func fetchMyFollowedArtistsForRockList(limit: Int = 50) async throws -> [SpotifyArtist] {
        var allArtists: [SpotifyArtist] = []
        var after: String? = nil
        
        repeat {
            let response = try await spotifyAPI.getFollowedArtists(
                limit: min(limit, 50),
                after: after
            )
            
            allArtists.append(contentsOf: response.artists.items)
            after = response.artists.next
            
            // Stop if we've reached the desired limit or there's no next page
            if allArtists.count >= limit || after == nil {
                break
            }
        } while allArtists.count < limit
        
        return Array(allArtists.prefix(limit))
    }
    
    // MARK: - User Profile & Region
    
    /// Fetches current user's Spotify profile including region info
    /// - Returns: User profile with country/region information
    func fetchUserProfile() async throws -> SpotifyUserProfile {
        return try await spotifyAPI.getCurrentUserProfile()
    }
    
    // MARK: - Helper Methods
    
    /// Fetches all top artists across all time ranges
    /// Useful for comprehensive RockList views
    func fetchAllTimeTopArtists(limit: Int = 20) async throws -> [SpotifyArtist] {
        async let shortTerm = fetchMyTopArtistsForRockList(timeRange: .shortTerm, limit: limit)
        async let mediumTerm = fetchMyTopArtistsForRockList(timeRange: .mediumTerm, limit: limit)
        async let longTerm = fetchMyTopArtistsForRockList(timeRange: .longTerm, limit: limit)
        
        let results = try await [shortTerm, mediumTerm, longTerm]
        
        // Combine and deduplicate by artist ID
        var seenIds = Set<String>()
        var uniqueArtists: [SpotifyArtist] = []
        
        for artists in results {
            for artist in artists {
                if !seenIds.contains(artist.id) {
                    seenIds.insert(artist.id)
                    uniqueArtists.append(artist)
                }
            }
        }
        
        return uniqueArtists
    }
    
    /// Fetches top tracks for a specific artist
    /// Useful for artist-specific RockList views
    func fetchTopTracksForArtist(
        artistId: String,
        timeRange: SpotifyAPI.SpotifyTimeRange = .mediumTerm,
        limit: Int = 20
    ) async throws -> [SpotifyTrack] {
        let response = try await spotifyAPI.getTopTracks(
            timeRange: timeRange,
            limit: limit
        )
        
        // Filter tracks by the specified artist
        return response.items.filter { track in
            track.artists.contains { $0.id == artistId }
        }
    }
    
    // MARK: - Ensure RockList Data for Artist
    
    /// Ensures RockList data exists for a specific artist
    /// This triggers data ingestion if needed
    func ensureRockListData(for artistId: String) async throws {
        // Check if we need to perform initial ingestion
        let lastIngested = try? await getLastIngestedTimestamp()
        
        if lastIngested == nil {
            // Perform initial bootstrap ingestion
            try await performInitialBootstrapIngestion()
        } else {
            // Perform incremental ingestion for recent plays
            try await performIncrementalIngestion()
        }
    }
    
    /// Ensures listening data is ingested for a specific artist
    /// Checks top tracks across all time ranges to find the artist
    /// Falls back to regular incremental ingestion if artist not found in top tracks
    func ensureArtistDataIngested(artistId: String) async throws {
        print("🔍 RockListDataService: Checking top tracks for artist \(artistId)...")
        
        let profile = try await spotifyAPI.getCurrentUserProfile()
        let region = profile.country ?? "GLOBAL"
        
        var events: [RockListPlayEvent] = []
        
        // Check top tracks across all time ranges
        do {
            async let shortTerm = spotifyAPI.getTopTracks(timeRange: .shortTerm, limit: 50)
            async let mediumTerm = spotifyAPI.getTopTracks(timeRange: .mediumTerm, limit: 50)
            async let longTerm = spotifyAPI.getTopTracks(timeRange: .longTerm, limit: 50)
            
            let (shortTermTracks, mediumTermTracks, longTermTracks) = try await (shortTerm, mediumTerm, longTerm)
            
            // Filter tracks by the target artist
            let allTracks = shortTermTracks.items + mediumTermTracks.items + longTermTracks.items
            let artistTracks = allTracks.filter { track in
                track.artists.contains { $0.id == artistId }
            }
            
            if !artistTracks.isEmpty {
                print("✅ RockListDataService: Found \(artistTracks.count) top tracks for artist")
                
                // Create play events for these tracks
                // Use current date for virtual events, with slight variation to simulate listening over time
                let now = Date()
                for (index, track) in artistTracks.enumerated() {
                    // Distribute events over the past few days to simulate natural listening
                    let daysAgo = Double(index % 7) // Spread over a week
                    let playedAt = now.addingTimeInterval(-daysAgo * 24 * 60 * 60)
                    
                    events.append(
                        RockListPlayEvent(
                            artistId: artistId,
                            artistName: track.artists.first(where: { $0.id == artistId })?.name ?? track.artists.first?.name ?? "Unknown",
                            trackId: track.id,
                            trackName: track.name,
                            playedAt: playedAt,
                            durationMs: track.durationMs,
                            region: region
                        )
                    )
                }
                
                // Send events to backend
                try await sendEventsToBackend(events)
                print("✅ RockListDataService: Ingested \(events.count) play events for artist from top tracks")
                return
            } else {
                print("ℹ️ RockListDataService: Artist not found in top tracks, falling back to incremental ingestion")
            }
        } catch {
            // If top tracks fetch fails, log and fall through to incremental ingestion
            print("⚠️ RockListDataService: Failed to fetch top tracks for artist: \(error.localizedDescription)")
        }
        
        // Fallback: perform regular incremental ingestion
        // This will capture the artist if they appear in recently played
        let lastIngested = try? await getLastIngestedTimestamp()
        try await performIncrementalIngestion(lastIngestedAt: lastIngested)
    }
}

