import Foundation


// MARK: - Data Models

struct RealYouMix {
    let title: String          // "The Real You"
    let subtitle: String       // "Your core sound right now"
    let description: String    // short vibe description
    let genres: [GenreStat]
    let tracks: [SpotifyTrack]
}

struct SoundprintForecast {
    let headline: String           // "Your 2025 Soundprint Forecast"
    let risingGenres: [GenreStat]  // genres likely to grow
    let wildcardGenres: [GenreStat]
    let suggestedTracks: [SpotifyTrack]
}

struct DiscoveryBundle {
    let newTracks: [SpotifyTrack]      // high-confidence recs
    let newArtists: [SpotifyArtist]    // artists they don't already listen to
    let newGenres: [String]            // genres they don't currently have
}

// MARK: - Discovery Engine

final class DiscoveryEngine {

    private let api: SpotifyAPI

    init(api: SpotifyAPI) {
        self.api = api
    }

    // MARK: - 1. The Real You Mix

    /// Builds the "The Real You" playlist based on core genres + top artists/tracks.
    func buildRealYouMix(
        genres: [GenreStat],
        topArtists: [SpotifyArtist],
        topTracks: [SpotifyTrack]
    ) async throws -> RealYouMix {

        let sortedGenres = genres.sorted { $0.percent > $1.percent }
        let coreGenres = Array(sortedGenres.prefix(3))

        let seedArtistIDs = Array(topArtists.prefix(3)).map { $0.id }
        let seedTrackIDs  = Array(topTracks.prefix(2)).map { $0.id }
        let seedGenres    = coreGenres.map { $0.genre.lowercased() }

        var recs: [SpotifyTrack] = []
        do {
            recs = try await api.getRecommendations(
                seedArtists: seedArtistIDs,
                seedGenres: seedGenres,
                seedTracks: seedTrackIDs,
                limit: 40
            )
        } catch {
            // Fallback: just use their own top tracks if recs fail
            recs = Array(topTracks.prefix(30))
        }

        // If Spotify returned nothing, still give them something to see
        if recs.isEmpty {
            recs = Array(topTracks.prefix(30))
        }

        let main = coreGenres.first?.genre.capitalized ?? "your sound"
        let desc = "Built from your heaviest-played sounds: \(main) and the lanes orbiting it."

        return RealYouMix(
            title: "The Real You",
            subtitle: "Your core sound right now",
            description: desc,
            genres: coreGenres,
            tracks: recs
        )
    }

    // MARK: - 2. Soundprint Forecast

    /// Heuristic forecast: promotes mid-tier genres as "rising",
    /// pulls recommendations seeded on those for a future-you feel.
    func buildForecast(
        genres: [GenreStat],
        topArtists: [SpotifyArtist],
        topTracks: [SpotifyTrack]
    ) async throws -> SoundprintForecast {

        // Rising = not your #1, but between 3% and 12% share
        let rising = genres
            .sorted { $0.percent > $1.percent }
            .filter { $0.percent >= 0.03 && $0.percent <= 0.12 }

        // Wildcards = small but present (< 4%)
        let wildcards = genres
            .filter { $0.percent > 0 && $0.percent < 0.04 }
            .sorted { $0.percent > $1.percent }

        let seedGenres = Array(rising.prefix(3)).map { $0.genre.lowercased() }
        let seedArtists = Array(topArtists.prefix(2)).map { $0.id }

        var forecastTracks: [SpotifyTrack] = []
        do {
            forecastTracks = try await api.getRecommendations(
                seedArtists: seedArtists,
                seedGenres: seedGenres,
                seedTracks: [],
                limit: 30
            )
        } catch {
            // Fallback: use a different seed set (e.g. just artists)
            do {
                forecastTracks = try await api.getRecommendations(
                    seedArtists: seedArtists,
                    seedGenres: [],
                    seedTracks: [],
                    limit: 30
                )
            } catch {
                // Final fallback: reuse some of their own top tracks
                forecastTracks = Array(topTracks.prefix(20))
            }
        }

        if forecastTracks.isEmpty {
            forecastTracks = Array(topTracks.prefix(20))
        }

        let headline: String
        if let first = rising.first {
            headline = "You’re drifting deeper into \(first.genre.capitalized)."
        } else if let first = genres.sorted(by: { $0.percent > $1.percent }).first {
            headline = "Expect more of your \(first.genre.capitalized) era."
        } else {
            headline = "Your 2025 Soundprint is still loading."
        }

        return SoundprintForecast(
            headline: headline,
            risingGenres: rising,
            wildcardGenres: wildcards,
            suggestedTracks: forecastTracks
        )
    }

    // MARK: - 3. Discovery Bundle (new music, artists, genres)

    func buildDiscoveryBundle(
        genres: [GenreStat],
        topArtists: [SpotifyArtist],
        topTracks: [SpotifyTrack]
    ) async throws -> DiscoveryBundle {

        let existingArtistIDs = Set(topArtists.map { $0.id })
        let existingGenres = Set(genres.map { $0.genre.lowercased() })
        let existingTrackIDs = Set(topTracks.map { $0.id })

        let seedArtists = Array(topArtists.prefix(3)).map { $0.id }
        let seedGenres  = Array(genres.prefix(3)).map { $0.genre.lowercased() }

        var recs: [SpotifyTrack] = []
        do {
            recs = try await api.getRecommendations(
                seedArtists: seedArtists,
                seedGenres: seedGenres,
                seedTracks: [],
                limit: 60
            )
        } catch {
            // Fallback: try artists only
            do {
                recs = try await api.getRecommendations(
                    seedArtists: seedArtists,
                    seedGenres: [],
                    seedTracks: [],
                    limit: 60
                )
            } catch {
                recs = []
            }
        }

        // Filter out already-known tracks
        let freshTracks = recs.filter { !existingTrackIDs.contains($0.id) }

        // New artists pulled from those tracks
        var newArtistMap: [String: SpotifyArtist] = [:]
        for track in freshTracks {
            for artist in track.artists {
                if !existingArtistIDs.contains(artist.id) {
                    newArtistMap[artist.id] = artist
                }
            }
        }
        let newArtists = Array(newArtistMap.values)

        // New genres from new artists
        var newGenreSet = Set<String>()
        for artist in newArtists {
            for g in artist.genres ?? [] {
                let lc = g.lowercased()
                if !existingGenres.contains(lc) {
                    newGenreSet.insert(g)
                }
            }
        }
        let newGenres = Array(newGenreSet).sorted()

        return DiscoveryBundle(
            newTracks: freshTracks,
            newArtists: newArtists,
            newGenres: newGenres
        )
    }
}
