import Foundation

@MainActor
final class SpotifyAPI: ObservableObject {

    private let auth = SpotifyAuthService.shared
    private let baseURL = "https://api.spotify.com/v1"

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
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "SpotifyAPI", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "API error: \(body)"])
        }
        return data
    }

    func getUserProfile() async throws -> SpotifyUserProfile {
        let data = try await authedRequest(path: "/me")
        return try JSONDecoder().decode(SpotifyUserProfile.self, from: data)
    }

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
    /// Wrapper over /recommendations endpoint
    func getRecommendations(
        seedArtists: [String] = [],
        seedGenres: [String] = [],
        seedTracks: [String] = [],
        limit: Int = 30
    ) async throws -> [SpotifyTrack] {

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if !seedArtists.isEmpty {
            queryItems.append(
                URLQueryItem(
                    name: "seed_artists",
                    value: seedArtists.joined(separator: ",")
                )
            )
        }
        if !seedGenres.isEmpty {
            queryItems.append(
                URLQueryItem(
                    name: "seed_genres",
                    value: seedGenres.joined(separator: ",")
                )
            )
        }
        if !seedTracks.isEmpty {
            queryItems.append(
                URLQueryItem(
                    name: "seed_tracks",
                    value: seedTracks.joined(separator: ",")
                )
            )
        }

        // Re-use your authedRequest helper
        let data = try await authedRequest(
            path: "/recommendations",
            queryItems: queryItems
        )

        return try JSONDecoder()
            .decode(SpotifyRecommendationsResponse.self, from: data)
            .tracks
    }
}
