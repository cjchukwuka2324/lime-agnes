import Foundation

/// Service for creating and managing Apple Music playlists
final class AppleMusicPlaylistService {
    static let shared = AppleMusicPlaylistService()
    private init() {}
    
    private let webAPI = AppleMusicWebAPI.shared
    private let authService = AppleMusicAuthService.shared
    private let appleMusicAPI = AppleMusicAPI.shared
    
    // MARK: - Create Playlist and Add Tracks
    
    func createPlaylistAndAddTracks(
        name: String,
        description: String?,
        trackIds: [String],
        isPublic: Bool = false // Apple Music doesn't have public playlists in the same way
    ) async throws -> String {
        let userToken = await MainActor.run {
            authService.userToken
        }
        guard let userToken = userToken else {
            throw NSError(
                domain: "AppleMusicPlaylistService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User not authorized. Please connect Apple Music in Settings."]
            )
        }
        
        // Create playlist
        let playlistId = try await webAPI.createPlaylist(
            userToken: userToken,
            name: name,
            description: description
        )
        
        // Add tracks (Apple Music Web API requires adding tracks in batches if many)
        let batchSize = 100 // Apple Music API limit
        for i in stride(from: 0, to: trackIds.count, by: batchSize) {
            let endIndex = min(i + batchSize, trackIds.count)
            let batch = Array(trackIds[i..<endIndex])
            try await webAPI.addTracksToPlaylist(
                userToken: userToken,
                playlistId: playlistId,
                trackIds: batch
            )
        }
        
        return playlistId
    }
    
    // MARK: - My Weekly Discovery Playlist
    
    /// Creates/updates "My Weekly Discovery" playlist (equivalent to Spotify's Discover Weekly)
    func createOrUpdateWeeklyDiscovery(userToken: String) async throws -> String {
        // Get user's top artists and tracks for recommendations
        let topArtistsResponse = try await appleMusicAPI.getTopArtists(limit: 20)
        let topTracksResponse = try await appleMusicAPI.getTopTracks(limit: 20)
        
        // Get genres from top artists
        let allGenres = Set(topArtistsResponse.items.flatMap { $0.genres ?? [] })
        
        // Search for similar artists and new releases
        var recommendedTrackIds: [String] = []
        
        // Search for new releases in favorite genres
        for genre in allGenres.prefix(5) {
            do {
                let searchResults = try await webAPI.search(
                    userToken: userToken,
                    query: genre,
                    types: ["songs"],
                    limit: 10
                )
                
                if let songs = searchResults.results.songs?.data {
                    let newTracks = songs.prefix(5).map { $0.id }
                    recommendedTrackIds.append(contentsOf: newTracks)
                }
            } catch {
                print("⚠️ Failed to search for genre \(genre): \(error)")
            }
        }
        
        // Search for similar artists
        for artist in topArtistsResponse.items.prefix(5) {
            do {
                let searchResults = try await webAPI.search(
                    userToken: userToken,
                    query: artist.name,
                    types: ["songs"],
                    limit: 5
                )
                
                if let songs = searchResults.results.songs?.data {
                    let similarTracks = songs.prefix(3).map { $0.id }
                    recommendedTrackIds.append(contentsOf: similarTracks)
                }
            } catch {
                print("⚠️ Failed to search for artist \(artist.name): \(error)")
            }
        }
        
        // Limit to 30 tracks total
        recommendedTrackIds = Array(Set(recommendedTrackIds)).prefix(30).map { $0 }
        
        // Create or update playlist
        let playlistName = "My Weekly Discovery"
        let playlistDescription = "Your personalized weekly music discovery, powered by RockOut"
        
        // Try to find existing playlist first (would need additional API call)
        // For now, create new one each time
        let playlistId = try await createPlaylistAndAddTracks(
            name: playlistName,
            description: playlistDescription,
            trackIds: Array(recommendedTrackIds)
        )
        
        return playlistId
    }
    
    // MARK: - New Release Radar Playlist
    
    /// Creates/updates "New Release Radar" playlist (equivalent to Spotify's Release Radar)
    func createOrUpdateReleaseRadar(userToken: String) async throws -> String {
        // Get user's top artists
        let topArtistsResponse = try await appleMusicAPI.getTopArtists(limit: 50)
        
        // Search for new releases from favorite artists
        var newReleaseTrackIds: [String] = []
        
        // Get current date and date 7 days ago
        let calendar = Calendar.current
        let today = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        // Search for new releases from top artists
        for artist in topArtistsResponse.items.prefix(20) {
            do {
                let searchResults = try await webAPI.search(
                    userToken: userToken,
                    query: "\(artist.name) new",
                    types: ["songs"],
                    limit: 10
                )
                
                if let songs = searchResults.results.songs?.data {
                    // Filter for recent releases (would need to check release date from catalog)
                    // For now, just take first few results
                    let recentTracks = songs.prefix(2).map { $0.id }
                    newReleaseTrackIds.append(contentsOf: recentTracks)
                }
            } catch {
                print("⚠️ Failed to search for new releases from \(artist.name): \(error)")
            }
        }
        
        // Limit to 50 tracks
        newReleaseTrackIds = Array(Set(newReleaseTrackIds)).prefix(50).map { $0 }
        
        // Create or update playlist
        let playlistName = "New Release Radar"
        let playlistDescription = "New releases from your favorite artists, updated weekly"
        
        let playlistId = try await createPlaylistAndAddTracks(
            name: playlistName,
            description: playlistDescription,
            trackIds: Array(newReleaseTrackIds)
        )
        
        return playlistId
    }
}

