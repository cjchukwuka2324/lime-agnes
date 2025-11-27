import Foundation

@MainActor
final class SpotifyAPI: ObservableObject {

    private let auth = SpotifyAuthService.shared
    private let baseURL = "https://api.spotify.com/v1"

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
        queryItems: [URLQueryItem]? = nil,
        retryOn401: Bool = true
    ) async throws -> Data {
        
        // Check if user is authorized before making request
        guard auth.isAuthorized() else {
            throw NSError(
                domain: "SpotifyAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Spotify authentication required"]
            )
        }

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

        // Handle 401 Unauthorized - try refreshing token once
        if http.statusCode == 401 && retryOn401 {
            // Force token refresh and retry once
            _ = try await auth.refreshAccessTokenIfNeeded()
            return try await authedRequest(path: path, queryItems: queryItems, retryOn401: false)
        }

        if !(200...299).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8) ?? "(no error body)"
            
            // Handle rate limiting
            if http.statusCode == 429 {
                if let retryAfter = http.value(forHTTPHeaderField: "Retry-After"),
                   let retrySeconds = Double(retryAfter) {
                    throw NSError(
                        domain: "SpotifyAPI",
                        code: 429,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Rate limit exceeded. Retry after \(retrySeconds) seconds.",
                            "RetryAfter": retrySeconds
                        ]
                    )
                }
            }
            
            throw NSError(
                domain: "SpotifyAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API error (\(http.statusCode)): \(bodyString)"]
            )
        }

        return data
    }

    // MARK: - Profile
    func getUserProfile() async throws -> SpotifyUserProfile {
        let data = try await authedRequest(path: "/me")
        return try JSONDecoder().decode(SpotifyUserProfile.self, from: data)
    }
    
    /// Alias for RockList compatibility
    func getCurrentUserProfile() async throws -> SpotifyUserProfile {
        return try await getUserProfile()
    }

    // MARK: - Time Range Enum
    enum SpotifyTimeRange: String {
        case shortTerm = "short_term"
        case mediumTerm = "medium_term"
        case longTerm = "long_term"
    }
    
    // MARK: - Top Artists
    func getTopArtists(limit: Int = 10) async throws -> [SpotifyArtist] {
        return try await getTopArtists(timeRange: .mediumTerm, limit: limit, offset: 0).items
    }
    
    func getTopArtists(
        timeRange: SpotifyTimeRange = .mediumTerm,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> SpotifyTopArtistsResponse {
        let data = try await authedRequest(
            path: "/me/top/artists",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "time_range", value: timeRange.rawValue)
            ]
        )

        return try JSONDecoder().decode(SpotifyTopArtistsResponse.self, from: data)
    }

    // MARK: - Top Tracks
    func getTopTracks(limit: Int = 10) async throws -> [SpotifyTrack] {
        return try await getTopTracks(timeRange: .mediumTerm, limit: limit, offset: 0).items
    }
    
    func getTopTracks(
        timeRange: SpotifyTimeRange = .mediumTerm,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> SpotifyTopTracksResponse {
        let data = try await authedRequest(
            path: "/me/top/tracks",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "offset", value: "\(offset)"),
                URLQueryItem(name: "time_range", value: timeRange.rawValue)
            ]
        )

        return try JSONDecoder().decode(SpotifyTopTracksResponse.self, from: data)
    }
    
    // MARK: - Recently Played
    func getRecentlyPlayed(
        limit: Int = 50,
        after: Date? = nil,
        before: Date? = nil
    ) async throws -> SpotifyRecentlyPlayedResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        if let after = after {
            let afterMs = Int64(after.timeIntervalSince1970 * 1000)
            queryItems.append(URLQueryItem(name: "after", value: "\(afterMs)"))
        }
        
        if let before = before {
            let beforeMs = Int64(before.timeIntervalSince1970 * 1000)
            queryItems.append(URLQueryItem(name: "before", value: "\(beforeMs)"))
        }
        
        let data = try await authedRequest(
            path: "/me/player/recently-played",
            queryItems: queryItems
        )
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SpotifyRecentlyPlayedResponse.self, from: data)
    }
    
    // MARK: - Following Artists
    func getFollowedArtists(
        limit: Int = 50,
        after: String? = nil
    ) async throws -> SpotifyFollowingArtistsResponse {
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
        
        return try JSONDecoder().decode(SpotifyFollowingArtistsResponse.self, from: data)
    }
    
    // MARK: - Artist Lookup
    func getArtist(id: String) async throws -> SpotifyArtist {
        let data = try await authedRequest(path: "/artists/\(id)")
        return try JSONDecoder().decode(SpotifyArtist.self, from: data)
    }
    
    func getArtists(ids: [String]) async throws -> [SpotifyArtist] {
        guard !ids.isEmpty else { return [] }
        
        // Spotify API allows up to 50 IDs per request
        let chunkSize = 50
        var allArtists: [SpotifyArtist] = []
        
        for chunk in ids.chunked(into: chunkSize) {
            let idsString = chunk.joined(separator: ",")
            let data = try await authedRequest(
                path: "/artists",
                queryItems: [URLQueryItem(name: "ids", value: idsString)]
            )
            
            struct ArtistsResponse: Codable {
                let artists: [SpotifyArtist]
            }
            
            let response = try JSONDecoder().decode(ArtistsResponse.self, from: data)
            allArtists.append(contentsOf: response.artists)
        }
        
        return allArtists
    }
    
    // MARK: - Track Lookup
    func getTracks(ids: [String]) async throws -> [SpotifyTrack] {
        guard !ids.isEmpty else { return [] }
        
        // Spotify API allows up to 50 IDs per request
        let chunkSize = 50
        var allTracks: [SpotifyTrack] = []
        
        for chunk in ids.chunked(into: chunkSize) {
            let idsString = chunk.joined(separator: ",")
            let data = try await authedRequest(
                path: "/tracks",
                queryItems: [URLQueryItem(name: "ids", value: idsString)]
            )
            
            struct TracksResponse: Codable {
                let tracks: [SpotifyTrack]
            }
            
            let response = try JSONDecoder().decode(TracksResponse.self, from: data)
            allTracks.append(contentsOf: response.tracks)
        }
        
        return allTracks
    }
    
    // MARK: - Audio Features
    func getAudioFeatures(ids: [String]) async throws -> [SpotifyAudioFeatures] {
        guard !ids.isEmpty else { return [] }
        
        // Spotify API allows up to 100 IDs per request for audio features
        let chunkSize = 100
        var allFeatures: [SpotifyAudioFeatures] = []
        
        for chunk in ids.chunked(into: chunkSize) {
            let idsString = chunk.joined(separator: ",")
            let data = try await authedRequest(
                path: "/audio-features",
                queryItems: [URLQueryItem(name: "ids", value: idsString)]
            )
            
            struct AudioFeaturesResponse: Codable {
                let audio_features: [SpotifyAudioFeatures]
            }
            
            let response = try JSONDecoder().decode(AudioFeaturesResponse.self, from: data)
            allFeatures.append(contentsOf: response.audio_features.compactMap { $0 })
        }
        
        return allFeatures
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

// MARK: - Array Chunking Helper
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
