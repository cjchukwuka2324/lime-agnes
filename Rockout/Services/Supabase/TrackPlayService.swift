import Foundation
import Supabase

final class TrackPlayService {
    static let shared = TrackPlayService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Check and Record Play
    
    /// Checks if threshold is reached and records the play if so.
    /// Threshold: 30 seconds for tracks > 30 sec, or 80% for tracks ≤ 30 sec
    /// - Parameters:
    ///   - trackId: The track being played
    ///   - albumId: The album containing the track
    ///   - durationListened: How long the user has listened in seconds
    ///   - trackDuration: Full duration of the track in seconds
    /// - Returns: True if play was recorded, false if threshold not met or already recorded
    func checkAndRecordPlay(
        trackId: UUID,
        albumId: UUID,
        durationListened: Double,
        trackDuration: Double
    ) async throws -> Bool {
        // Check if threshold is reached
        let thresholdReached = shouldRecordPlay(
            durationListened: durationListened,
            trackDuration: trackDuration
        )
        
        guard thresholdReached else {
            return false
        }
        
        // Check if user already recorded a play for this track recently (within last 30 seconds)
        // This prevents rapid-fire duplicate recordings while allowing legitimate re-plays
        let recentPlay = try await hasRecentPlay(trackId: trackId, withinSeconds: 30)
        guard !recentPlay else {
            return false // Already recorded recently
        }
        
        // Record the play
        try await recordPlay(
            trackId: trackId,
            albumId: albumId,
            durationListened: durationListened,
            trackDuration: trackDuration,
            thresholdReached: true
        )
        
        // Check if this is a discovered album and mark completion if threshold reached
        try? await markAlbumCompletionIfNeeded(albumId: albumId)
        
        return true
    }
    
    // MARK: - Private Helpers
    
    private func shouldRecordPlay(durationListened: Double, trackDuration: Double) -> Bool {
        // For tracks 30 seconds or less, require 80% playback
        if trackDuration <= 30.0 {
            let threshold = trackDuration * 0.8
            return durationListened >= threshold
        }
        // For tracks longer than 30 seconds, require 30 seconds playback
        else {
            return durationListened >= 30.0
        }
    }
    
    private func recordPlay(
        trackId: UUID,
        albumId: UUID,
        durationListened: Double,
        trackDuration: Double,
        thresholdReached: Bool
    ) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        struct TrackPlayDTO: Encodable {
            let track_id: String
            let album_id: String
            let user_id: String
            let duration_listened: Double
            let track_duration: Double
            let threshold_reached: Bool
        }
        
        let playDTO = TrackPlayDTO(
            track_id: trackId.uuidString,
            album_id: albumId.uuidString,
            user_id: userId,
            duration_listened: durationListened,
            track_duration: trackDuration,
            threshold_reached: thresholdReached
        )
        
        try await supabase
            .from("track_plays")
            .insert(playDTO)
            .execute()
        
        print("✅ Recorded track play: track=\(trackId), duration=\(durationListened)s, threshold=\(thresholdReached)")
    }
    
    private func hasRecentPlay(trackId: UUID, withinSeconds: Int) async throws -> Bool {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Check if user has recorded a play for this track within the last N seconds
        // This prevents duplicate recordings from rapid-fire threshold checks
        let cutoffTime = Date().addingTimeInterval(-Double(withinSeconds))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cutoffTimeString = formatter.string(from: cutoffTime)
        
        // Check for recent plays - use created_at since it's set immediately on insert
        // played_at might have a default value that's slightly different
        let response = try await supabase
            .from("track_plays")
            .select("id")
            .eq("track_id", value: trackId.uuidString)
            .eq("user_id", value: userId)
            .gte("created_at", value: cutoffTimeString)
            .limit(1)
            .execute()
        
        let plays = try JSONDecoder().decode([TrackPlayRecord].self, from: response.data)
        return !plays.isEmpty
    }
    
    // MARK: - Get Play Counts
    
    /// Gets aggregated play counts for all tracks in an album.
    /// Only accessible by album owners and collaborators.
    /// - Parameter albumId: The album to get play counts for
    /// - Returns: Dictionary mapping track_id to play count
    func getPlayCounts(for albumId: UUID) async throws -> [UUID: Int] {
        let response = try await supabase
            .from("track_play_counts")
            .select("track_id, play_count")
            .eq("album_id", value: albumId.uuidString)
            .execute()
        
        struct PlayCountResponse: Codable {
            let track_id: UUID
            let play_count: Int
        }
        
        let counts = try JSONDecoder().decode([PlayCountResponse].self, from: response.data)
        
        var result: [UUID: Int] = [:]
        for count in counts {
            result[count.track_id] = count.play_count
        }
        
        return result
    }
    
    /// Gets play count for a specific track.
    /// Only accessible by album owners and collaborators.
    /// - Parameter trackId: The track to get play count for
    /// - Returns: The play count, or 0 if no plays recorded
    func getPlayCount(for trackId: UUID) async throws -> Int {
        let response = try await supabase
            .from("track_play_counts")
            .select("play_count")
            .eq("track_id", value: trackId.uuidString)
            .limit(1)
            .execute()
        
        struct PlayCountResponse: Codable {
            let play_count: Int
        }
        
        let counts = try JSONDecoder().decode([PlayCountResponse].self, from: response.data)
        return counts.first?.play_count ?? 0
    }
    
    // MARK: - Get Play Counts Per User
    
    /// Gets play counts per user for a specific track.
    /// Only accessible by album owners and collaborators.
    /// - Parameter trackId: The track to get per-user play counts for
    /// - Returns: Array of user play count records, sorted by play count descending
    func getPlayCountsPerUser(for trackId: UUID) async throws -> [UserPlayCount] {
        // First, get all play records for this track (threshold_reached = true only)
        let playsResponse = try await supabase
            .from("track_plays")
            .select("user_id")
            .eq("track_id", value: trackId.uuidString)
            .eq("threshold_reached", value: true)
            .execute()
        
        // Parse and aggregate play counts by user_id
        let rawPlays = try JSONSerialization.jsonObject(with: playsResponse.data, options: []) as? [[String: Any]] ?? []
        
        var userPlayCountsDict: [String: Int] = [:]
        for play in rawPlays {
            if let userIdString = play["user_id"] as? String {
                userPlayCountsDict[userIdString, default: 0] += 1
            }
        }
        
        // Get unique user IDs
        let userIds = Array(userPlayCountsDict.keys.compactMap { UUID(uuidString: $0) })
        guard !userIds.isEmpty else { return [] }
        
        // Fetch profile information for all users who played the track
        var userPlayCounts: [UserPlayCount] = []
        
        for (userIdString, playCount) in userPlayCountsDict {
            guard let userId = UUID(uuidString: userIdString) else { continue }
            
            // Fetch profile for this user
            var profileInfo = UserPlayCount.ProfileInfo(
                username: nil,
                displayName: nil,
                firstName: nil,
                lastName: nil,
                profilePictureURL: nil
            )
            
            do {
                struct ProfileResponse: Codable {
                    let username: String?
                    let display_name: String?
                    let first_name: String?
                    let last_name: String?
                    let profile_picture_url: String?
                }
                
                let profileResponse = try await supabase
                    .from("profiles")
                    .select("username, display_name, first_name, last_name, profile_picture_url")
                    .eq("id", value: userIdString)
                    .single()
                    .execute()
                
                let profile = try JSONDecoder().decode(ProfileResponse.self, from: profileResponse.data)
                
                profileInfo = UserPlayCount.ProfileInfo(
                    username: profile.username,
                    displayName: profile.display_name,
                    firstName: profile.first_name,
                    lastName: profile.last_name,
                    profilePictureURL: profile.profile_picture_url.flatMap { URL(string: $0) }
                )
            } catch {
                print("⚠️ Failed to fetch profile for user \(userIdString): \(error.localizedDescription)")
                // Continue with empty profile info
            }
            
            userPlayCounts.append(UserPlayCount(
                userId: userId,
                playCount: playCount,
                profile: profileInfo
            ))
        }
        
        // Sort by play count descending
        return userPlayCounts.sorted { $0.playCount > $1.playCount }
    }
    
    // MARK: - Helper Models
    
    private struct TrackPlayRecord: Codable {
        let id: UUID
    }
    
    // MARK: - Public Models
    
    struct UserPlayCount: Identifiable {
        let userId: UUID
        let playCount: Int
        let profile: ProfileInfo
        
        var id: UUID { userId }
        
        struct ProfileInfo {
            let username: String?
            let displayName: String?
            let firstName: String?
            let lastName: String?
            let profilePictureURL: URL?
            
            var displayNameOrUsername: String {
                if let displayName = displayName, !displayName.isEmpty {
                    return displayName
                }
                if let firstName = firstName, let lastName = lastName {
                    return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                }
                if let firstName = firstName {
                    return firstName
                }
                if let username = username, !username.isEmpty {
                    return "@\(username)"
                }
                return "Unknown User"
            }
            
            var handle: String {
                if let username = username, !username.isEmpty {
                    return "@\(username)"
                }
                return ""
            }
        }
    }
    
    // MARK: - Discover Album Completion Tracking
    
    /// Marks an album as completed in discovered_albums if user has saved it from Discover feed
    private func markAlbumCompletionIfNeeded(albumId: UUID) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        // Check if user has this album in discovered_albums
        struct DiscoveredAlbumResponse: Codable {
            let id: UUID
            let completed_listen: Bool
        }
        
        let response = try? await supabase
            .from("discovered_albums")
            .select("id, completed_listen")
            .eq("user_id", value: userId.uuidString)
            .eq("album_id", value: albumId.uuidString)
            .single()
            .execute()
        
        guard let discoveredAlbum = try? JSONDecoder().decode(DiscoveredAlbumResponse.self, from: response?.data ?? Data()) else {
            // Album not in discovered_albums, nothing to update
            return
        }
        
        // If not already completed, mark as completed
        if !discoveredAlbum.completed_listen {
            try await supabase
                .from("discovered_albums")
                .update(["completed_listen": true])
                .eq("id", value: discoveredAlbum.id.uuidString)
                .execute()
            
            print("✅ Marked discovered album \(albumId) as completed for user \(userId)")
        }
    }
    
    /// Increments replay count for a discovered album when user plays it again after completing
    func incrementReplayCountIfNeeded(albumId: UUID) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        // Check if user has this album in discovered_albums and has completed it
        struct DiscoveredAlbumResponse: Codable {
            let id: UUID
            let completed_listen: Bool
            let replay_count: Int
        }
        
        let response = try? await supabase
            .from("discovered_albums")
            .select("id, completed_listen, replay_count")
            .eq("user_id", value: userId.uuidString)
            .eq("album_id", value: albumId.uuidString)
            .single()
            .execute()
        
        guard let discoveredAlbum = try? JSONDecoder().decode(DiscoveredAlbumResponse.self, from: response?.data ?? Data()) else {
            // Album not in discovered_albums, nothing to update
            return
        }
        
        // Only increment if already completed
        if discoveredAlbum.completed_listen {
            try await supabase
                .from("discovered_albums")
                .update(["replay_count": discoveredAlbum.replay_count + 1])
                .eq("id", value: discoveredAlbum.id.uuidString)
                .execute()
            
            print("✅ Incremented replay count for discovered album \(albumId) for user \(userId)")
        }
    }
}

