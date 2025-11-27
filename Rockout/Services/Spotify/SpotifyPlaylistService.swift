import Foundation

/// Service for creating and managing Spotify playlists
final class SpotifyPlaylistService {
    static let shared = SpotifyPlaylistService()
    private init() {}
    
    private let authService = SpotifyAuthService.shared
    
    /// Create a playlist and add tracks to Spotify
    func createPlaylistAndAddTracks(
        name: String,
        description: String,
        trackUris: [String],
        isPublic: Bool = false
    ) async throws -> String {
        // Check authorization on main actor
        let isAuthorized = await MainActor.run {
            authService.isAuthorized()
        }
        
        guard isAuthorized else {
            throw NSError(domain: "SpotifyPlaylistService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authorized with Spotify"])
        }
        
        // Get access token on main actor
        let accessToken = await MainActor.run {
            authService.accessToken
        }
        
        guard let accessToken = accessToken, !accessToken.isEmpty else {
            throw NSError(domain: "SpotifyPlaylistService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No valid access token"])
        }
        
        // Get user ID
        let userId = try await getUserId(accessToken: accessToken)
        
        // Create playlist
        let playlistId = try await createPlaylist(
            userId: userId,
            name: name,
            description: description,
            isPublic: isPublic,
            accessToken: accessToken
        )
        
        // Add tracks in batches (Spotify allows max 100 tracks per request)
        let batchSize = 100
        for i in stride(from: 0, to: trackUris.count, by: batchSize) {
            let batch = Array(trackUris[i..<min(i + batchSize, trackUris.count)])
            try await addTracksToPlaylist(
                playlistId: playlistId,
                trackUris: batch,
                accessToken: accessToken
            )
        }
        
        return playlistId
    }
    
    // MARK: - Private Methods
    
    private func getUserId(accessToken: String) async throws -> String {
        let url = URL(string: "https://api.spotify.com/v1/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "SpotifyPlaylistService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to get user ID"])
        }
        
        struct UserResponse: Codable {
            let id: String
        }
        
        let user = try JSONDecoder().decode(UserResponse.self, from: data)
        return user.id
    }
    
    private func createPlaylist(
        userId: String,
        name: String,
        description: String,
        isPublic: Bool,
        accessToken: String
    ) async throws -> String {
        let url = URL(string: "https://api.spotify.com/v1/users/\(userId)/playlists")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct CreatePlaylistRequest: Codable {
            let name: String
            let description: String
            let `public`: Bool
        }
        
        let body = CreatePlaylistRequest(name: name, description: description, public: isPublic)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "SpotifyPlaylistService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create playlist: \(errorMessage)"])
        }
        
        struct PlaylistResponse: Codable {
            let id: String
        }
        
        let playlist = try JSONDecoder().decode(PlaylistResponse.self, from: data)
        return playlist.id
    }
    
    private func addTracksToPlaylist(
        playlistId: String,
        trackUris: [String],
        accessToken: String
    ) async throws {
        let urisString = trackUris.joined(separator: ",")
        let url = URL(string: "https://api.spotify.com/v1/playlists/\(playlistId)/tracks?uris=\(urisString)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            throw NSError(domain: "SpotifyPlaylistService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to add tracks to playlist"])
        }
    }
}

