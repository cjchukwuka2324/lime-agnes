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
    /// Fetches the actual storefront from Apple Music API
    func getUserStorefront() async throws -> String {
        // Try to fetch actual storefront from /me/storefront endpoint
        do {
            let data = try await request(path: "/me/storefront", userToken: nil)
            
            struct StorefrontResponse: Codable {
                let data: [StorefrontData]
            }
            
            struct StorefrontData: Codable {
                let id: String
                let type: String
                let attributes: StorefrontAttributes
            }
            
            struct StorefrontAttributes: Codable {
                let name: String
                let defaultLanguageTag: String
                let supportedLanguageTags: [String]
            }
            
            let response = try JSONDecoder().decode(StorefrontResponse.self, from: data)
            if let storefront = response.data.first {
                print("✅ Apple Music storefront: \(storefront.id) (\(storefront.attributes.name))")
                return storefront.id
            }
        } catch {
            print("⚠️ Failed to fetch storefront, using default: \(error.localizedDescription)")
        }
        
        // Fallback to US if fetch fails
        return "us"
    }
    
    // MARK: - API Request Helper
    
    /// Make a request to Apple Music Web API using MusicKit's automatic token generation
    /// MusicDataRequest automatically includes the developer token in the Authorization header
    private func request(
        path: String,
        method: String = "GET",
        userToken: String? = nil,
        body: Data? = nil,
        requireUserAuth: Bool = true
    ) async throws -> Data {
        // For catalog searches, we don't need user authorization, just developer token
        // MusicDataRequest will handle developer token automatically
        if requireUserAuth {
            // Ensure MusicKit authorization for user-specific endpoints
            guard await MusicAuthorization.request() == .authorized else {
                throw NSError(
                    domain: "AppleMusicWebAPI",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "MusicKit authorization is required. Please authorize Apple Music access."]
                )
            }
        }
        
        guard let url = URL(string: baseURL + path) else {
            throw NSError(domain: "AppleMusicWebAPI", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Create URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        
        if let body = body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        // Use MusicDataRequest to automatically handle both developer token and Music User Token
        // MusicDataRequest wraps URLRequest and automatically adds:
        // 1. Authorization header with developer token (automatic token generation)
        // 2. Music-User-Token header for personalized requests (if MusicKit is authorized)
        // Note: userToken parameter is kept for backward compatibility but typically not needed
        // as MusicDataRequest automatically handles Music-User-Token when MusicKit is authorized
        if #available(iOS 16.0, *) {
            let musicRequest = MusicDataRequest(urlRequest: urlRequest)
            let response = try await musicRequest.response()
            
            guard let httpResponse = response.urlResponse as? HTTPURLResponse else {
                throw NSError(domain: "AppleMusicWebAPI", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                let errorBody = String(data: response.data, encoding: .utf8) ?? "Unknown error"
                
                if httpResponse.statusCode == 401 {
                    throw NSError(
                        domain: "AppleMusicWebAPI",
                        code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Could not authenticate with Apple Music. Please ensure MusicKit is properly configured and you have an active Apple Music subscription."]
                    )
                }
                
                throw NSError(
                    domain: "AppleMusicWebAPI",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "API error (\(httpResponse.statusCode)): \(errorBody)"]
                )
            }
            
            return response.data
        } else {
            // Fallback for iOS < 16: Use URLSession (requires manual developer token)
            // This should not be used in production, but included for compatibility
            throw NSError(
                domain: "AppleMusicWebAPI",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Apple Music Web API requires iOS 16.0 or later for automatic token generation."]
            )
        }
    }
    
    // MARK: - User Library
    
    func getUserLibrarySongs(userToken: String? = nil, limit: Int = 100) async throws -> [AppleMusicWebAPISong] {
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
    
    func getHeavyRotationArtists(userToken: String? = nil, limit: Int = 20) async throws -> [AppleMusicWebAPIArtist] {
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
    
    func getHeavyRotationSongs(userToken: String? = nil, limit: Int = 20) async throws -> [AppleMusicWebAPISong] {
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
    
    func getRecentlyPlayed(userToken: String? = nil, limit: Int = 50) async throws -> [AppleMusicWebAPIPlayHistory] {
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
    
    func createPlaylist(userToken: String? = nil, name: String, description: String?) async throws -> String {
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
    
    func addTracksToPlaylist(userToken: String? = nil, playlistId: String, trackIds: [String]) async throws {
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
    
    func search(userToken: String? = nil, query: String, types: [String] = ["songs", "artists"], limit: Int = 20) async throws -> AppleMusicWebAPISearchResponse {
        let storefront = try await getUserStorefront()
        let typesString = types.joined(separator: ",")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        
        let data = try await request(
            path: "/catalog/\(storefront)/search?term=\(encodedQuery)&types=\(typesString)&limit=\(limit)",
            userToken: userToken
        )
        
        return try JSONDecoder().decode(AppleMusicWebAPISearchResponse.self, from: data)
    }
    
    // MARK: - Public Search (No User Authentication Required)
    
    /// Public catalog search that works without user authentication
    /// Uses catalog endpoint which only requires developer token (handled by MusicKit)
    func searchPublic(query: String, types: [String] = ["songs"], limit: Int = 20) async throws -> AppleMusicWebAPISearchResponse {
        // Ensure authorization status is determined (doesn't require user to authorize)
        // MusicDataRequest requires status to be determined, but catalog searches work even if denied
        let currentStatus = MusicAuthorization.currentStatus
        if currentStatus == .notDetermined {
            // Request once to determine status - user can deny, that's fine for catalog searches
            let requestedStatus = await MusicAuthorization.request()
            if requestedStatus == .denied {
                print("⚠️ Apple Music authorization denied, but catalog search will still work")
            }
        }
        
        // Use default storefront (US) for public search
        // In production, you might want to detect user's storefront
        let storefront = "us"
        let typesString = types.joined(separator: ",")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        
        // Public catalog search - only needs developer token, not user token
        // requireUserAuth: false means we don't need user authorization for catalog searches
        let data = try await request(
            path: "/catalog/\(storefront)/search?term=\(encodedQuery)&types=\(typesString)&limit=\(limit)",
            userToken: nil, // No user token needed for catalog search
            requireUserAuth: false // Catalog searches don't require user auth
        )
        
        return try JSONDecoder().decode(AppleMusicWebAPISearchResponse.self, from: data)
    }
    
    /// Search for playlists publicly
    func searchPlaylistsPublic(query: String, limit: Int = 20) async throws -> [AppleMusicWebAPISong] {
        // Note: Apple Music catalog search doesn't support playlist search directly
        // We'll search for songs and return them
        // For playlists, users would need to paste the URL
        let response = try await searchPublic(query: query, types: ["songs"], limit: limit)
        return response.results.songs?.data ?? []
    }
}

