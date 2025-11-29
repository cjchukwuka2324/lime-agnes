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

// MARK: - Search and Track/Playlist Methods
extension SpotifyAPI {
    
    // MARK: - Search Tracks
    func searchTracks(query: String, limit: Int = 20) async throws -> [SpotifyTrack] {
        // Validate query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NSError(domain: "SpotifyAPI", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Search query cannot be empty"])
        }
        
        let data = try await authedRequest(
            path: "/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "track"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        
        // Check if response is empty
        guard !data.isEmpty else {
            throw NSError(domain: "SpotifyAPI", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Empty response from Spotify API"])
        }
        
        // Debug: Print raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔍 Spotify search response: \(responseString.prefix(500))")
        }
        
        do {
            let response = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
            let tracks = response.tracks?.items ?? []
            
            // Log preview URL availability for debugging
            for track in tracks {
                if let previewURL = track.previewURL {
                    print("✅ Track '\(track.name)' has preview URL: \(previewURL.absoluteString)")
                } else {
                    print("⚠️ Track '\(track.name)' has NO preview URL available")
                }
            }
            
            return tracks
        } catch let decodingError {
            print("❌ Failed to decode search response: \(decodingError)")
            
            // Try to decode as a simpler structure in case Spotify API changed
            // Manually decode to ensure preview_url is captured
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let tracksDict = json["tracks"] as? [String: Any],
                   let items = tracksDict["items"] as? [Any] {
                    var tracks: [SpotifyTrack] = []
                    for item in items {
                        // Skip null items
                        if item is NSNull {
                            continue
                        }
                        
                        guard let itemDict = item as? [String: Any] else {
                            continue
                        }
                        
                        // Extract preview_url explicitly to ensure it's captured
                        let previewUrlString = itemDict["preview_url"] as? String
                        
                        // Try to decode the full track
                        if let itemData = try? JSONSerialization.data(withJSONObject: itemDict),
                           var track = try? JSONDecoder().decode(SpotifyTrack.self, from: itemData) {
                            // Ensure preview_url is set (in case decoding missed it)
                            // Note: Since SpotifyTrack is a struct, we can't modify it directly
                            // But the decoder should handle it correctly
                            if let previewUrl = previewUrlString {
                                print("🎵 Found preview URL for track '\(track.name)': \(previewUrl)")
                            } else {
                                print("⚠️ No preview URL for track '\(track.name)'")
                            }
                            tracks.append(track)
                        }
                    }
                    return tracks
                } else {
                    // Response structure is different than expected
                    print("⚠️ Unexpected response structure: \(json.keys.joined(separator: ", "))")
                    throw NSError(domain: "SpotifyAPI", code: -3,
                                 userInfo: [NSLocalizedDescriptionKey: "Unexpected response format from Spotify API"])
                }
            } else {
                // Can't parse as JSON at all
                throw NSError(domain: "SpotifyAPI", code: -4,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response from Spotify API: \(decodingError.localizedDescription)"])
            }
        }
    }
    
    // MARK: - Search Playlists
    func searchPlaylists(query: String, limit: Int = 20) async throws -> [SpotifyPlaylist] {
        // Validate query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NSError(domain: "SpotifyAPI", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Search query cannot be empty"])
        }
        
        let data = try await authedRequest(
            path: "/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "type", value: "playlist"),
                URLQueryItem(name: "limit", value: "\(limit)")
            ]
        )
        
        // Check if response is empty
        guard !data.isEmpty else {
            throw NSError(domain: "SpotifyAPI", code: -2,
                         userInfo: [NSLocalizedDescriptionKey: "Empty response from Spotify API"])
        }
        
        // Debug: Print raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("🔍 Spotify playlist search response: \(responseString.prefix(500))")
        }
        
        do {
            let response = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
            return response.playlists?.items ?? []
        } catch let decodingError {
            print("❌ Failed to decode playlist search response: \(decodingError)")
            
            // Try to decode as a simpler structure in case Spotify API changed
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let playlistsDict = json["playlists"] as? [String: Any],
                   let items = playlistsDict["items"] as? [[String: Any]] {
                    let decoder = JSONDecoder()
                    var playlists: [SpotifyPlaylist] = []
                    for item in items {
                        if let itemData = try? JSONSerialization.data(withJSONObject: item),
                           let playlist = try? decoder.decode(SpotifyPlaylist.self, from: itemData) {
                            playlists.append(playlist)
                        }
                    }
                    return playlists
                } else {
                    // Response structure is different than expected
                    print("⚠️ Unexpected response structure: \(json.keys.joined(separator: ", "))")
                    throw NSError(domain: "SpotifyAPI", code: -3,
                                 userInfo: [NSLocalizedDescriptionKey: "Unexpected response format from Spotify API"])
                }
            } else {
                // Can't parse as JSON at all
                throw NSError(domain: "SpotifyAPI", code: -4,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response from Spotify API: \(decodingError.localizedDescription)"])
            }
        }
    }
    
    // MARK: - Get Track
    func getTrack(spotifyId: String) async throws -> SpotifyTrack {
        let data = try await authedRequest(path: "/tracks/\(spotifyId)")
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: data)
        
        // Log preview URL availability
        if let previewURL = track.previewURL {
            print("✅ Track '\(track.name)' fetched with preview URL: \(previewURL.absoluteString)")
        } else {
            print("⚠️ Track '\(track.name)' fetched but has NO preview URL available")
        }
        
        return track
    }
    
    // MARK: - Get Playlist
    func getPlaylist(spotifyId: String) async throws -> SpotifyPlaylist {
        let data = try await authedRequest(path: "/playlists/\(spotifyId)")
        return try JSONDecoder().decode(SpotifyPlaylist.self, from: data)
    }
    
    // MARK: - Parse Spotify URL
    func parseSpotifyURL(_ urlString: String) -> (type: String, id: String)? {
        // Spotify URL formats:
        // https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh
        // https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M
        // spotify:track:4iV5W9uYEdYUVa79Axb7Rh
        // spotify:playlist:37i9dQZF1DXcBWIGoYBM5M
        
        let urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle spotify: URI scheme
        if urlString.hasPrefix("spotify:") {
            let components = urlString.split(separator: ":")
            if components.count >= 3 {
                let type = String(components[1]) // track or playlist
                let id = String(components[2])
                if type == "track" || type == "playlist" {
                    return (type: type, id: id)
                }
            }
        }
        
        // Handle https://open.spotify.com URLs
        if let url = URL(string: urlString),
           url.host?.contains("spotify.com") == true || url.host?.contains("spotify.link") == true {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            
            if pathComponents.count >= 2 {
                let type = pathComponents[0] // track or playlist
                let id = pathComponents[1]
                if type == "track" || type == "playlist" {
                    return (type: type, id: id)
                }
            }
        }
        
        // Handle shortened spotify.link URLs - these redirect, so we'd need to follow redirects
        // For now, return nil and let the caller handle it
        return nil
    }
}
