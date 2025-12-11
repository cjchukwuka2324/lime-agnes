import Foundation
import MusicKit
import Combine

@MainActor
final class AppleMusicAPI: ObservableObject {
    static let shared = AppleMusicAPI()
    private let webAPI = AppleMusicWebAPI.shared
    private let authService = AppleMusicAuthService.shared
    
    private init() {}
    
    // MARK: - Get User Token / Verify Authorization
    
    /// Verify that Apple Music is authorized and connection exists
    /// Note: We don't need the actual user token since MusicDataRequest handles it automatically
    private func verifyAuthorization() async throws {
        // Check if MusicKit is authorized
        guard await MusicAuthorization.request() == .authorized else {
            throw NSError(
                domain: "AppleMusicAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authorized. Please connect Apple Music in Settings."]
            )
        }
        
        // Check if we have a connection record
        let connection = await MainActor.run {
            authService.appleMusicConnection
        }
        guard connection != nil else {
            throw NSError(
                domain: "AppleMusicAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Apple Music connection not found. Please connect Apple Music in Settings."]
            )
        }
    }
    
    // MARK: - User Profile & Account Info
    
    /// Get Apple Music account information including subscription status and storefront
    func getAccountInfo() async throws -> AppleMusicAccountInfo {
        try await verifyAuthorization()
        
        // Get subscription status
        let subscription = try await MusicSubscription.current
        let canPlayCatalog = subscription.canPlayCatalogContent
        
        // Get storefront
        let storefront = try await webAPI.getUserStorefront()
        
        // Get connection info and parse connected_at date
        let connection = await MainActor.run {
            authService.appleMusicConnection
        }
        
        // Parse connected_at string to Date
        let connectedAt: Date? = {
            guard let dateString = connection?.connected_at else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)
        }()
        
        return AppleMusicAccountInfo(
            storefront: storefront,
            canPlayCatalogContent: canPlayCatalog,
            hasCloudLibrary: false, // MusicSubscription doesn't expose this property directly
            connectedAt: connectedAt
        )
    }
    
    func getCurrentUserProfile() async throws -> AppleMusicUserProfile {
        // Try to get from connection if available
        let connection = await MainActor.run {
            authService.appleMusicConnection
        }
        
        // Get account info for display name
        let accountInfo = try? await getAccountInfo()
        let storefront = accountInfo?.storefront ?? "us"
        
        if let connection = connection {
            // Use storefront as display identifier since we can't get email/name
            let displayName = connection.display_name ?? "Apple Music (\(storefront.uppercased()))"
            
            return AppleMusicUserProfile(
                id: connection.apple_music_user_id,
                displayName: displayName,
                email: connection.email
            )
        }
        
        // Fallback to generated ID with storefront info
        let userId = UUID().uuidString
        return AppleMusicUserProfile(
            id: userId,
            displayName: "Apple Music (\(storefront.uppercased()))",
            email: nil
        )
    }
    
    // MARK: - Recently Played
    
    func getRecentlyPlayed(limit: Int = 50, after: Date? = nil) async throws -> AppleMusicRecentlyPlayedResponse {
        try await verifyAuthorization()
        
        // Try Web API first (MusicDataRequest will automatically include Music-User-Token)
        do {
            // Pass nil for userToken - MusicDataRequest will handle it automatically
            let webAPIHistory = try await webAPI.getRecentlyPlayed(userToken: nil, limit: limit)
            
            let items = webAPIHistory.compactMap { history -> AppleMusicPlayHistory? in
                guard let song = history.attributes.song else { return nil }
                // Convert Web API song to AppleMusicTrack
                let track = AppleMusicTrack(from: song)
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let playedAt = formatter.date(from: history.attributes.playDate)
                
                return AppleMusicPlayHistory(track: track, playedAt: playedAt)
            }
            
            return AppleMusicRecentlyPlayedResponse(items: items)
        } catch {
            // Fallback: Try MusicKit library access
            print("⚠️ Web API failed for recently played, trying MusicKit fallback: \(error)")
            // For now, return empty. Can implement MusicKit library access later
            return AppleMusicRecentlyPlayedResponse(items: [])
        }
    }
    
    // MARK: - Top Artists
    
    /// Get top artists based on listening history from recently played data
    /// This provides accurate personal listening data, unlike Heavy Rotation charts
    func getTopArtists(timeRange: AppleMusicTimeRange = .mediumTerm, limit: Int = 20) async throws -> AppleMusicTopArtistsResponse {
        try await verifyAuthorization()
        
        print("🎵 Fetching top artists from listening history (time range: \(timeRange.rawValue))")
        
        // Calculate date cutoff based on time range
        let calendar = Calendar.current
        let now = Date()
        let cutoffDate: Date
        switch timeRange {
        case .shortTerm:
            cutoffDate = calendar.date(byAdding: .day, value: -28, to: now) ?? now // Last 4 weeks
        case .mediumTerm:
            cutoffDate = calendar.date(byAdding: .month, value: -6, to: now) ?? now // Last 6 months
        case .longTerm:
            cutoffDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now // Last year
        }
        
        // Get recently played data (fetch more to get accurate stats)
        let fetchLimit = min(limit * 10, 200) // Fetch more to have better statistics
        let recentlyPlayedResponse = try await getRecentlyPlayed(limit: fetchLimit)
        
        // Filter by date and count plays per artist
        var artistPlayCounts: [String: (artist: AppleMusicArtist, count: Int)] = [:]
        
        for item in recentlyPlayedResponse.items {
            // Filter by time range
            if let playedAt = item.playedAt, playedAt >= cutoffDate {
                // Count each artist for this track
                for artist in item.track.artists {
                    let artistKey = artist.id.isEmpty ? artist.name.lowercased() : artist.id
                    
                    if let existing = artistPlayCounts[artistKey] {
                        artistPlayCounts[artistKey] = (artist: existing.artist, count: existing.count + 1)
                    } else {
                        artistPlayCounts[artistKey] = (artist: artist, count: 1)
                    }
                }
            }
        }
        
        // Sort by play count and take top N
        let topArtists = artistPlayCounts.values
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0.artist }
        
        print("✅ Found \(topArtists.count) top artists from listening history")
        return AppleMusicTopArtistsResponse(items: Array(topArtists))
    }
    
    // MARK: - Top Tracks
    
    /// Get top tracks based on listening history from recently played data
    /// This provides accurate personal listening data, unlike Heavy Rotation charts
    func getTopTracks(timeRange: AppleMusicTimeRange = .mediumTerm, limit: Int = 20) async throws -> AppleMusicTopTracksResponse {
        try await verifyAuthorization()
        
        print("🎵 Fetching top tracks from listening history (time range: \(timeRange.rawValue))")
        
        // Calculate date cutoff based on time range
        let calendar = Calendar.current
        let now = Date()
        let cutoffDate: Date
        switch timeRange {
        case .shortTerm:
            cutoffDate = calendar.date(byAdding: .day, value: -28, to: now) ?? now // Last 4 weeks
        case .mediumTerm:
            cutoffDate = calendar.date(byAdding: .month, value: -6, to: now) ?? now // Last 6 months
        case .longTerm:
            cutoffDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now // Last year
        }
        
        // Get recently played data (fetch more to get accurate stats)
        let fetchLimit = min(limit * 5, 200) // Fetch more to have better statistics
        let recentlyPlayedResponse = try await getRecentlyPlayed(limit: fetchLimit)
        
        // Filter by date and count plays per track
        var trackPlayCounts: [String: (track: AppleMusicTrack, count: Int)] = [:]
        
        for item in recentlyPlayedResponse.items {
            // Filter by time range
            if let playedAt = item.playedAt, playedAt >= cutoffDate {
                let trackKey = item.track.id
                
                if let existing = trackPlayCounts[trackKey] {
                    trackPlayCounts[trackKey] = (track: existing.track, count: existing.count + 1)
                } else {
                    trackPlayCounts[trackKey] = (track: item.track, count: 1)
                }
            }
        }
        
        // Sort by play count and take top N
        let topTracks = trackPlayCounts.values
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0.track }
        
        print("✅ Found \(topTracks.count) top tracks from listening history")
        return AppleMusicTopTracksResponse(items: Array(topTracks))
    }
}

// MARK: - Time Range Enum

enum AppleMusicTimeRange: String, Codable {
    case shortTerm = "short_term"
    case mediumTerm = "medium_term"
    case longTerm = "long_term"
}
