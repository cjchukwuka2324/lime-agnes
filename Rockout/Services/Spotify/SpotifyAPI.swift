import Foundation

@MainActor
final class SpotifyAPI: ObservableObject {

    private let auth = SpotifyAuthService.shared
    private let baseURL = "https://api.spotify.com/v1"
    
    // MARK: - Spotify Time Range
    
    enum SpotifyTimeRange: String, CaseIterable {
        case shortTerm = "short_term"    // ~4 weeks
        case mediumTerm = "medium_term"  // ~6 months
        case longTerm = "long_term"      // ~several years
    }

    // Allowed Spotify recommendation genres (Spotify’s official subset)
    private let allowedSeedGenres: Set<String> = [
        "acoustic","afrobeat","alt-rock","alternative","ambient","bluegrass","blues",
        "bossanova","chicago-house","classical","club","comedy","country","dance",
        "dancehall","death-metal","deep-house","detroit-techno","disco","drill",
        "dub","dubstep","edm","electronic","emo","folk","forro","french","funk",
        "garage","gospel","goth","grindcore","groove","grunge","hard-rock","hardcore",
        "heavy-metal","hip-hop","honky-tonk","house","indie","indie-pop","industrial",
        "j-pop","jazz","k-pop","latin","latino","metal","metalcore","minimal-techno",
        "opera","pagode","party","piano","pop","progressive-house","punk","punk-rock",
        "r-n-b","reggae","reggaeton","rock","rock-n-roll","rockabilly","romance",
        "sad","salsa","samba","singer-songwriter","ska","soul","spanish","swedish",
        "synth-pop","tech-house","techno","trance","trap","trip-hop","turkish","world"
    ]

    // MARK: - Authed GET request
    private func authedRequest(
        path: String,
        queryItems: [URLQueryItem]? = nil
    ) async throws -> Data {

        let token = try await auth.refreshAccessTokenIfNeeded()

        var components = URLComponents(string: baseURL + path)!
        if let queryItems = queryItems {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw NSError(domain: "SpotifyAPI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "SpotifyAPI", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        if !(200...299).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "(no error body)"
            
            // Provide user-friendly error messages for common status codes
            let errorMessage: String
            switch http.statusCode {
            case 401:
                errorMessage = "Authentication failed. Please reconnect your Spotify account."
            case 403:
                errorMessage = "Access denied. Please check your Spotify app settings:\n\n1. Go to https://developer.spotify.com/dashboard\n2. Open your app settings\n3. Make sure 'rockout://auth' is added to Redirect URIs\n4. If your app is in Development mode, add your Spotify email to Users and Access\n5. Save and wait 1-2 minutes for changes to take effect"
            case 404:
                errorMessage = "Spotify resource not found. Please try again."
            case 429:
                errorMessage = "Too many requests. Please wait a moment and try again."
            case 500...599:
                errorMessage = "Spotify server error. Please try again later."
            default:
                errorMessage = "API error (\(http.statusCode)): \(bodyString)"
            }
            
            throw NSError(
                domain: "SpotifyAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
        }

        return data
    }

    // MARK: - Profile
    func getUserProfile() async throws -> SpotifyUserProfile {
        let data = try await authedRequest(path: "/me")
        return try JSONDecoder().decode(SpotifyUserProfile.self, from: data)
    }
    
    // Alias for compatibility
    func getCurrentUserProfile() async throws -> SpotifyUserProfile {
        return try await getUserProfile()
    }
    
    // MARK: - Recently Played
    func getRecentlyPlayed(limit: Int = 20, after: Date? = nil) async throws -> SpotifyRecentlyPlayedResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        if let after = after {
            // Convert Date to Unix timestamp in milliseconds
            let timestampMs = Int64(after.timeIntervalSince1970 * 1000)
            queryItems.append(URLQueryItem(name: "after", value: "\(timestampMs)"))
        }
        
        let data = try await authedRequest(
            path: "/me/player/recently-played",
            queryItems: queryItems
        )
        return try JSONDecoder().decode(SpotifyRecentlyPlayedResponse.self, from: data)
    }
    
    // MARK: - Followed Artists
    func getFollowedArtists(limit: Int = 20, after: String? = nil) async throws -> SpotifyFollowedArtistsResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "artist"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        if let after = after {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }
        
        let data = try await authedRequest(
            path: "/me/following",
            queryItems: queryItems
        )
        return try JSONDecoder().decode(SpotifyFollowedArtistsResponse.self, from: data)
    }

    // MARK: - Top Artists
    func getTopArtists(timeRange: SpotifyTimeRange = .mediumTerm, limit: Int = 10) async throws -> SpotifyTopArtistsResponse {
        let data = try await authedRequest(
            path: "/me/top/artists",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "time_range", value: timeRange.rawValue)
            ]
        )

        return try JSONDecoder().decode(SpotifyTopArtistsResponse.self, from: data)
    }

    // MARK: - Top Tracks
    func getTopTracks(timeRange: SpotifyTimeRange = .mediumTerm, limit: Int = 10) async throws -> SpotifyTopTracksResponse {
        let data = try await authedRequest(
            path: "/me/top/tracks",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "time_range", value: timeRange.rawValue)
            ]
        )

        return try JSONDecoder().decode(SpotifyTopTracksResponse.self, from: data)
    }
    
    // MARK: - Get Artist(s)
    
    /// Fetch a single artist by ID
    func getArtist(id: String) async throws -> SpotifyArtist {
        let data = try await authedRequest(path: "/artists/\(id)")
        return try JSONDecoder().decode(SpotifyArtist.self, from: data)
    }
    
    /// Fetch multiple artists by IDs (up to 50 at a time)
    func getArtists(ids: [String]) async throws -> [SpotifyArtist] {
        guard !ids.isEmpty else { return [] }
        
        // Spotify API allows up to 50 IDs at a time
        var allArtists: [SpotifyArtist] = []
        let chunkSize = 50
        
        for i in stride(from: 0, to: ids.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, ids.count)
            let chunk = Array(ids[i..<endIndex])
            let idsString = chunk.joined(separator: ",")
            
            let data = try await authedRequest(
                path: "/artists",
                queryItems: [
                    URLQueryItem(name: "ids", value: idsString)
                ]
            )
            
            struct ArtistsResponse: Codable {
                let artists: [SpotifyArtist]
            }
            
            let response = try JSONDecoder().decode(ArtistsResponse.self, from: data)
            allArtists.append(contentsOf: response.artists)
        }
        
        return allArtists
    }
}


// MARK: - Recommendations
extension SpotifyAPI {

    func filteredGenres(_ rawGenres: [String]) -> [String] {
        rawGenres
            .map { $0.lowercased() }
            .filter { allowedSeedGenres.contains($0) }
    }

    func getRecommendations(
        seedArtists: [String],
        seedGenres: [String],
        seedTracks: [String],
        limit: Int = 50
    ) async throws -> [SpotifyTrack] {

        // Clean seeds to avoid invalid seed errors
        let safeGenres = filteredGenres(seedGenres).prefix(3)
        let safeArtists = seedArtists.prefix(3)
        let safeTracks = seedTracks.prefix(3)

        var query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if !safeArtists.isEmpty {
            query.append(URLQueryItem(
                name: "seed_artists",
                value: safeArtists.joined(separator: ",")
            ))
        }

        if !safeGenres.isEmpty {
            query.append(URLQueryItem(
                name: "seed_genres",
                value: safeGenres.joined(separator: ",")
            ))
        }

        if !safeTracks.isEmpty {
            query.append(URLQueryItem(
                name: "seed_tracks",
                value: safeTracks.joined(separator: ",")
            ))
        }

        let data = try await authedRequest(
            path: "/recommendations",
            queryItems: query
        )

        struct RecResponse: Codable {
            let tracks: [SpotifyTrack]
        }

        return try JSONDecoder().decode(RecResponse.self, from: data).tracks
    }
}

// MARK: - Playlists
extension SpotifyAPI {
    
    struct SpotifyPlaylist: Codable, Identifiable {
        let id: String
        let name: String
        let description: String?
        let owner: SpotifyPlaylistOwner?
        let tracks: SpotifyPlaylistTracks?
        
        struct SpotifyPlaylistOwner: Codable {
            let id: String
            let display_name: String?
        }
        
        struct SpotifyPlaylistTracks: Codable {
            let total: Int
            let href: String
        }
    }
    
    struct SpotifyPlaylistsResponse: Codable {
        let items: [SpotifyPlaylist]
        let next: String?
    }
    
    struct SpotifyPlaylistTracksResponse: Codable {
        let items: [SpotifyPlaylistTrackItem]
        let next: String?
        
        struct SpotifyPlaylistTrackItem: Codable {
            let track: SpotifyTrack?
        }
    }
    
    /// Get user's playlists
    func getUserPlaylists(limit: Int = 50, offset: Int = 0) async throws -> SpotifyPlaylistsResponse {
        let data = try await authedRequest(
            path: "/me/playlists",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
        )
        return try JSONDecoder().decode(SpotifyPlaylistsResponse.self, from: data)
    }
    
    /// Get all user playlists (handles pagination)
    func getAllUserPlaylists() async throws -> [SpotifyPlaylist] {
        var allPlaylists: [SpotifyPlaylist] = []
        var offset = 0
        let limit = 50
        
        while true {
            let response = try await getUserPlaylists(limit: limit, offset: offset)
            allPlaylists.append(contentsOf: response.items)
            
            if response.next == nil {
                break
            }
            offset += limit
        }
        
        return allPlaylists
    }
    
    /// Find Discover Weekly playlist
    func findDiscoverWeekly() async throws -> SpotifyPlaylist? {
        let playlists = try await getAllUserPlaylists()
        return playlists.first { playlist in
            playlist.name.lowercased().contains("discover weekly")
        }
    }
    
    /// Find Release Radar playlist
    func findReleaseRadar() async throws -> SpotifyPlaylist? {
        let playlists = try await getAllUserPlaylists()
        return playlists.first { playlist in
            playlist.name.lowercased().contains("release radar")
        }
    }
    
    /// Get tracks from a playlist
    func getPlaylistTracks(playlistId: String, limit: Int = 100, offset: Int = 0) async throws -> SpotifyPlaylistTracksResponse {
        let data = try await authedRequest(
            path: "/playlists/\(playlistId)/tracks",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)")
            ]
        )
        return try JSONDecoder().decode(SpotifyPlaylistTracksResponse.self, from: data)
    }
    
    /// Get all tracks from a playlist (handles pagination)
    func getAllPlaylistTracks(playlistId: String) async throws -> [SpotifyTrack] {
        var allTracks: [SpotifyTrack] = []
        var offset = 0
        let limit = 100
        
        while true {
            let response = try await getPlaylistTracks(playlistId: playlistId, limit: limit, offset: offset)
            let tracks = response.items.compactMap { $0.track }
            allTracks.append(contentsOf: tracks)
            
            if response.next == nil {
                break
            }
            offset += limit
        }
        
        return allTracks
    }
}
