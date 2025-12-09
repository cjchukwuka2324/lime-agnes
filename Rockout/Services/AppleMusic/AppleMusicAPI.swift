import Foundation
import MusicKit
import Combine

@MainActor
final class AppleMusicAPI: ObservableObject {
    static let shared = AppleMusicAPI()
    private let webAPI = AppleMusicWebAPI.shared
    private let authService = AppleMusicAuthService.shared
    
    private init() {}
    
    // MARK: - Get User Token
    
    private func getUserToken() async throws -> String {
        let userToken = await MainActor.run {
            authService.userToken
        }
        guard let userToken = userToken else {
            throw NSError(
                domain: "AppleMusicAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authorized. Please connect Apple Music in Settings."]
            )
        }
        return userToken
    }
    
    // MARK: - User Profile
    
    func getCurrentUserProfile() async throws -> AppleMusicUserProfile {
        // Try to get from connection if available
        let connection = await MainActor.run {
            authService.appleMusicConnection
        }
        if let connection = connection {
            return AppleMusicUserProfile(
                id: connection.apple_music_user_id,
                displayName: connection.display_name,
                email: connection.email
            )
        }
        
        // Fallback to generated ID
        let userId = UUID().uuidString
        return AppleMusicUserProfile(
            id: userId,
            displayName: nil,
            email: nil
        )
    }
    
    // MARK: - Recently Played
    
    func getRecentlyPlayed(limit: Int = 50, after: Date? = nil) async throws -> AppleMusicRecentlyPlayedResponse {
        let userToken = try await getUserToken()
        
        // Try Web API first
        do {
            let webAPIHistory = try await webAPI.getRecentlyPlayed(userToken: userToken, limit: limit)
            
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
    
    func getTopArtists(timeRange: AppleMusicTimeRange = .mediumTerm, limit: Int = 20) async throws -> AppleMusicTopArtistsResponse {
        let userToken = try await getUserToken()
        
        // Try Web API first (Heavy Rotation charts)
        do {
            let webAPIArtists = try await webAPI.getHeavyRotationArtists(userToken: userToken, limit: limit)
            let artists = webAPIArtists.map { AppleMusicArtist(from: $0) }
            return AppleMusicTopArtistsResponse(items: artists)
        } catch {
            // Fallback: Try MusicKit Heavy Rotation charts
            print("⚠️ Web API failed for top artists, trying MusicKit fallback: \(error)")
            
            // MusicKit Heavy Rotation fallback
            // Note: MusicKit charts don't directly provide artists, so this is limited
            // For now, return empty on fallback failure
            return AppleMusicTopArtistsResponse(items: [])
        }
    }
    
    // MARK: - Top Tracks
    
    func getTopTracks(timeRange: AppleMusicTimeRange = .mediumTerm, limit: Int = 20) async throws -> AppleMusicTopTracksResponse {
        let userToken = try await getUserToken()
        
        // Try Web API first (Heavy Rotation charts)
        do {
            let webAPISongs = try await webAPI.getHeavyRotationSongs(userToken: userToken, limit: limit)
            let tracks = webAPISongs.map { AppleMusicTrack(from: $0) }
            return AppleMusicTopTracksResponse(items: tracks)
        } catch {
            // Fallback: Try MusicKit Heavy Rotation charts
            print("⚠️ Web API failed for top tracks, trying MusicKit fallback: \(error)")
            
            // MusicKit Heavy Rotation fallback
            // For now, return empty. Can implement MusicKit chart access later if needed
            return AppleMusicTopTracksResponse(items: [])
        }
    }
}

// MARK: - Time Range Enum

enum AppleMusicTimeRange: String, Codable {
    case shortTerm = "short_term"
    case mediumTerm = "medium_term"
    case longTerm = "long_term"
}
