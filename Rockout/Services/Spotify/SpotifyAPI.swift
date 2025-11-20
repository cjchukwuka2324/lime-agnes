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

    // MARK: - Top Artists
    func getTopArtists(limit: Int = 10) async throws -> [SpotifyArtist] {
        let data = try await authedRequest(
            path: "/me/top/artists",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "time_range", value: "medium_term")
            ]
        )

        return try JSONDecoder().decode(SpotifyTopArtistsResponse.self, from: data).items
    }

    // MARK: - Top Tracks
    func getTopTracks(limit: Int = 10) async throws -> [SpotifyTrack] {
        let data = try await authedRequest(
            path: "/me/top/tracks",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(limit)"),
                URLQueryItem(name: "time_range", value: "medium_term")
            ]
        )

        return try JSONDecoder().decode(SpotifyTopTracksResponse.self, from: data).items
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
