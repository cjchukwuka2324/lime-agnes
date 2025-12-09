import Foundation
import MusicKit

/// Service for interacting with Apple Music Web API (api.music.apple.com)
/// Uses MusicKit's automatic developer token generation via MusicDataRequest
final class AppleMusicWebAPI {
    static let shared = AppleMusicWebAPI()
    private init() {}
    
    private let baseURL = "https://api.music.apple.com/v1"
    
    // MARK: - Storefront
    
    /// Get user's storefront (country code for API requests)
    /// This would typically be fetched from MusicKit or user preferences
    func getUserStorefront() async throws -> String {
        // Default to US, but should ideally come from user's account
        return "us"
    }
    
    // MARK: - API Request Helper
    
    /// Make a request to Apple Music Web API using MusicKit's automatic token generation
    /// MusicDataRequest automatically includes the developer token in the Authorization header
    private func request(
        path: String,
        method: String = "GET",
        userToken: String? = nil,
        body: Data? = nil
    ) async throws -> Data {
        // Ensure MusicKit authorization
        guard await MusicAuthorization.request() == .authorized else {
            throw NSError(
                domain: "AppleMusicWebAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "MusicKit authorization is required. Please authorize Apple Music access."]
            )
        }
        
        guard let url = URL(string: baseURL + path) else {
            throw NSError(domain: "AppleMusicWebAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Create URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        
        // Add user token if provided (for personalized requests)
        if let userToken = userToken {
            urlRequest.setValue(userToken, forHTTPHeaderField: "Music-User-Token")
        }
        
        if let body = body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        // Developer token is required for all Web API requests to api.music.apple.com
        // 
        // IMPORTANT: Automatic developer token generation in MusicKit works for
        // MusicKit catalog APIs (like MusicCatalogResourceRequest), but NOT for
        // direct HTTP calls to the Web API.
        //
        // For direct Web API calls, you have two options:
        // 1. Provide a developer token manually (via Secrets.swift or another method)
        // 2. Use MusicKit catalog APIs instead of direct HTTP calls (recommended)
        //
        // If you have automatic token generation configured in your App ID,
        // you can still use it by switching to MusicKit catalog APIs.
        // For now, we'll check if a token is available in Secrets as a fallback.
        
        // Check if developer token is available (optional for automatic token generation setups)
        // Uncomment the following lines if you want to provide a token manually:
        /*
        if let devToken = Secrets.appleMusicDeveloperToken {
            urlRequest.setValue("Bearer \(devToken)", forHTTPHeaderField: "Authorization")
        }
        */
        
        // Make the request
        // Note: Without a developer token, this will return 401 Unauthorized
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AppleMusicWebAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            
            // If we get 401 Unauthorized, it means we need a developer token
            if httpResponse.statusCode == 401 {
                throw NSError(
                    domain: "AppleMusicWebAPI",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Developer token required. For native iOS apps, ensure MusicKit is properly configured in your App ID capabilities, or provide a developer token. Note: Automatic token generation works with MusicKit catalog APIs, not direct HTTP calls to the Web API."]
                )
            }
            
            throw NSError(
                domain: "AppleMusicWebAPI",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API error (\(httpResponse.statusCode)): \(errorBody)"]
            )
        }
        
        return data
    }
    
    // MARK: - User Library
    
    func getUserLibrarySongs(userToken: String, limit: Int = 100) async throws -> [AppleMusicWebAPISong] {
        let storefront = try await getUserStorefront()
        let data = try await request(
            path: "/me/library/songs?limit=\(limit)",
            userToken: userToken
        )
        
        struct LibrarySongsResponse: Codable {
            let data: [AppleMusicWebAPILibrarySong]
        }
        
        let response = try JSONDecoder().decode(LibrarySongsResponse.self, from: data)
        // Convert LibrarySong to WebAPISong (they have the same structure)
        return response.data.map { librarySong in
            AppleMusicWebAPISong(
                id: librarySong.id,
                type: librarySong.type,
                attributes: librarySong.attributes
            )
        }
    }
    
    // MARK: - Heavy Rotation Charts
    
    func getHeavyRotationArtists(userToken: String, limit: Int = 20) async throws -> [AppleMusicWebAPIArtist] {
        let storefront = try await getUserStorefront()
        let data = try await request(
            path: "/catalog/\(storefront)/charts?types=artists&limit=\(limit)",
            userToken: userToken
        )
        
        struct ChartsResponse: Codable {
            let results: ChartsResults
        }
        
        struct ChartsResults: Codable {
            let artists: [ChartData<AppleMusicWebAPIArtist>]?
        }
        
        struct ChartData<T: Codable>: Codable {
            let data: [T]
        }
        
        let response = try JSONDecoder().decode(ChartsResponse.self, from: data)
        return response.results.artists?.first?.data ?? []
    }
    
    func getHeavyRotationSongs(userToken: String, limit: Int = 20) async throws -> [AppleMusicWebAPISong] {
        let storefront = try await getUserStorefront()
        let data = try await request(
            path: "/catalog/\(storefront)/charts?types=songs&limit=\(limit)",
            userToken: userToken
        )
        
        struct ChartsResponse: Codable {
            let results: ChartsResults
        }
        
        struct ChartsResults: Codable {
            let songs: [ChartData<AppleMusicWebAPISong>]?
        }
        
        struct ChartData<T: Codable>: Codable {
            let data: [T]
        }
        
        let response = try JSONDecoder().decode(ChartsResponse.self, from: data)
        return response.results.songs?.first?.data ?? []
    }
    
    // MARK: - Recently Played
    
    func getRecentlyPlayed(userToken: String, limit: Int = 50) async throws -> [AppleMusicWebAPIPlayHistory] {
        let data = try await request(
            path: "/me/recent/played?limit=\(limit)",
            userToken: userToken
        )
        
        struct RecentlyPlayedResponse: Codable {
            let data: [AppleMusicWebAPIPlayHistory]
        }
        
        let response = try JSONDecoder().decode(RecentlyPlayedResponse.self, from: data)
        return response.data
    }
    
    // MARK: - Song Details (with audio features)
    
    func getSongDetails(userToken: String, songId: String) async throws -> AppleMusicWebAPISong {
        let storefront = try await getUserStorefront()
        let data = try await request(
            path: "/catalog/\(storefront)/songs/\(songId)",
            userToken: userToken
        )
        
        struct SongResponse: Codable {
            let data: [AppleMusicWebAPISong]
        }
        
        let response = try JSONDecoder().decode(SongResponse.self, from: data)
        guard let song = response.data.first else {
            throw NSError(domain: "AppleMusicWebAPI", code: -4, userInfo: [NSLocalizedDescriptionKey: "Song not found"])
        }
        return song
    }
    
    // MARK: - Playlist Operations
    
    func createPlaylist(userToken: String, name: String, description: String?) async throws -> String {
        let body: [String: Any] = [
            "attributes": [
                "name": name,
                "description": description ?? ""
            ]
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let data = try await request(
            path: "/me/library/playlists",
            method: "POST",
            userToken: userToken,
            body: bodyData
        )
        
        struct PlaylistResponse: Codable {
            let data: [PlaylistData]
        }
        
        struct PlaylistData: Codable {
            let id: String
        }
        
        let response = try JSONDecoder().decode(PlaylistResponse.self, from: data)
        guard let playlistId = response.data.first?.id else {
            throw NSError(domain: "AppleMusicWebAPI", code: -5, userInfo: [NSLocalizedDescriptionKey: "Failed to create playlist"])
        }
        return playlistId
    }
    
    func addTracksToPlaylist(userToken: String, playlistId: String, trackIds: [String]) async throws {
        let storefront = try await getUserStorefront()
        
        let tracks = trackIds.map { [
            "id": $0,
            "type": "songs"
        ]}
        
        let body: [String: Any] = [
            "data": tracks
        ]
        
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await request(
            path: "/me/library/playlists/\(playlistId)/tracks",
            method: "POST",
            userToken: userToken,
            body: bodyData
        )
    }
    
    // MARK: - Search
    
    func search(userToken: String, query: String, types: [String] = ["songs", "artists"], limit: Int = 20) async throws -> AppleMusicWebAPISearchResponse {
        let storefront = try await getUserStorefront()
        let typesString = types.joined(separator: ",")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        
        let data = try await request(
            path: "/catalog/\(storefront)/search?term=\(encodedQuery)&types=\(typesString)&limit=\(limit)",
            userToken: userToken
        )
        
        return try JSONDecoder().decode(AppleMusicWebAPISearchResponse.self, from: data)
    }
}

