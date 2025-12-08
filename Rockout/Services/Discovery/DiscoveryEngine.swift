import Foundation

// MARK: - Data Models

struct RealYouMix {
    let title: String
    let subtitle: String
    let description: String
    let genres: [GenreStat]
    let tracks: [SpotifyTrack]
    
    init(title: String, subtitle: String, description: String, genres: [GenreStat], tracks: [SpotifyTrack]) {
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.genres = genres
        self.tracks = tracks
    }
}

struct SoundprintForecast {
    let headline: String
    let risingGenres: [GenreStat]
    let wildcardGenres: [GenreStat]
    let suggestedTracks: [SpotifyTrack]
    
    init(headline: String, risingGenres: [GenreStat], wildcardGenres: [GenreStat], suggestedTracks: [SpotifyTrack]) {
        self.headline = headline
        self.risingGenres = risingGenres
        self.wildcardGenres = wildcardGenres
        self.suggestedTracks = suggestedTracks
    }
}

struct DiscoveryBundle {
    let newTracks: [SpotifyTrack]
    let newArtists: [SpotifyArtist]
    let newGenres: [String]
    
    init(newTracks: [SpotifyTrack], newArtists: [SpotifyArtist], newGenres: [String]) {
        self.newTracks = newTracks
        self.newArtists = newArtists
        self.newGenres = newGenres
    }
}

// MARK: - Discovery Engine

final class DiscoveryEngine {

    private let api: SpotifyAPI

    init(api: SpotifyAPI) {
        self.api = api
    }

    // MARK: - 1. The Real You Mix
    /// 70% user's real favorites, 30% strong related recommendations.
    func buildRealYouMix(
        genres: [GenreStat],
        topArtists: [SpotifyArtist],
        topTracks: [SpotifyTrack]
    ) async throws -> RealYouMix {

        guard !topTracks.isEmpty else {
            throw NSError(domain: "DiscoveryEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No top tracks available"])
        }

        let sortedGenres = genres.sorted { $0.percent > $1.percent }
        let coreGenres = Array(sortedGenres.prefix(3))

        // Tight, high-confidence seeds
        let seedTrackIDs = Array(topTracks.prefix(3)).map { $0.id }
        let seedArtistIDs = Array(topArtists.prefix(2)).map { $0.id }
        let seedGenres = Array(coreGenres.prefix(2)).map { $0.genre.lowercased() }

        let knownTrackIDs = Set(topTracks.map { $0.id })

        let recs: [SpotifyTrack]
        do {
            let result = try await api.getRecommendations(
                seedArtists: seedArtistIDs,
                seedGenres: seedGenres,
                seedTracks: seedTrackIDs,
                limit: 40
            )
            recs = result.filter { !knownTrackIDs.contains($0.id) }
        } catch {
            print("⚠️ RealYouMix fallback: using artists + tracks only")
            let fallback = try await api.getRecommendations(
                seedArtists: seedArtistIDs,
                seedGenres: [],
                seedTracks: seedTrackIDs,
                limit: 40
            )
            recs = fallback.filter { !knownTrackIDs.contains($0.id) }
        }

        // Playlist composition
        let coreCount = 20
        let recCount = 10

        let mainTracks = Array(topTracks.prefix(coreCount))
        let recTracks = Array(recs.prefix(recCount))

        let final = mainTracks + recTracks

        let desc = "Built from your core: \(coreGenres.first?.genre.capitalized ?? "your sound")."

        return RealYouMix(
            title: "The Real You",
            subtitle: "Your core sound right now",
            description: desc,
            genres: coreGenres,
            tracks: final
        )
    }

    // MARK: - 2. Soundprint Forecast
    /// Uses rising + wildcard genres and mid-tier artists. 100% fresh tracks.
    func buildForecast(
        genres: [GenreStat],
        topArtists: [SpotifyArtist],
        topTracks: [SpotifyTrack]
    ) async throws -> SoundprintForecast {

        let sorted = genres.sorted { $0.percent > $1.percent }

        // Wildcards = tiny emerging genres
        let wildcards = sorted.filter { $0.percent > 0 && $0.percent < 0.035 }

        // Rising = mid-tier genre slices
        let rising = sorted.filter { $0.percent >= 0.035 && $0.percent < 0.12 }

        let knownTrackIDs = Set(topTracks.map { $0.id })

        // Choose seeds based on what's present
        let seedGenres: [String]
        if !wildcards.isEmpty {
            seedGenres = Array(wildcards.prefix(3)).map { $0.genre.lowercased() }
        } else if !rising.isEmpty {
            seedGenres = Array(rising.prefix(3)).map { $0.genre.lowercased() }
        } else {
            seedGenres = Array(sorted.dropFirst(2).prefix(2)).map { $0.genre.lowercased() }
        }

        // Use mid-tier artists (skip their top 2)
        let seedArtists = Array(topArtists.dropFirst(2).prefix(3)).map { $0.id }

        let raw: [SpotifyTrack]
        do {
            raw = try await api.getRecommendations(
                seedArtists: seedArtists,
                seedGenres: seedGenres,
                seedTracks: [],
                limit: 70
            )
        } catch {
            print("⚠️ Forecast fallback: genres only")
            raw = try await api.getRecommendations(
                seedArtists: [],
                seedGenres: seedGenres,
                seedTracks: [],
                limit: 70
            )
        }

        let freshTracks = raw.filter { !knownTrackIDs.contains($0.id) }
        let finalTracks = Array(freshTracks.prefix(30))

        let headline: String
        if let w = wildcards.first {
            headline = "You're drifting into \(w.genre.capitalized)."
        } else if let r = rising.first {
            headline = "Your \(r.genre.capitalized) phase is rising."
        } else if sorted.count > 2 {
            headline = "Expect more of your \(sorted[2].genre.capitalized) era."
        } else {
            headline = "Your soundprint is shifting."
        }

        return SoundprintForecast(
            headline: headline,
            risingGenres: rising,
            wildcardGenres: wildcards,
            suggestedTracks: finalTracks
        )
    }

    // MARK: - 3. Discovery Bundle
    /// Wide exploration: new artists, new genres, new tracks.
    func buildDiscoveryBundle(
        genres: [GenreStat],
        topArtists: [SpotifyArtist],
        topTracks: [SpotifyTrack]
    ) async throws -> DiscoveryBundle {

        let knownTrackIDs = Set(topTracks.map { $0.id })
        let knownArtistIDs = Set(topArtists.map { $0.id })
        let knownGenreSet = Set(genres.map { $0.genre.lowercased() })

        // Wide exploration seeds: many genres, many artists
        let seedGenres = Array(genres.prefix(6)).map { $0.genre.lowercased() }
        let seedArtists = Array(topArtists.prefix(4)).map { $0.id }

        let raw = try await api.getRecommendations(
            seedArtists: seedArtists,
            seedGenres: seedGenres,
            seedTracks: [],
            limit: 80
        )

        // Strictly new tracks
        let fresh = raw.filter { !knownTrackIDs.contains($0.id) }

        // Extract new artists
        var newArtistMap: [String: SpotifyArtist] = [:]
        for t in fresh {
            for a in t.artists {
                if !knownArtistIDs.contains(a.id) {
                    newArtistMap[a.id] = a
                }
            }
        }
        let newArtists = Array(newArtistMap.values)

        // Extract brand-new genres
        var newGenreSet = Set<String>()
        for artist in newArtists {
            for g in artist.genres ?? [] {
                if !knownGenreSet.contains(g.lowercased()) {
                    newGenreSet.insert(g)
                }
            }
        }

        let newGenres = Array(newGenreSet).sorted()

        return DiscoveryBundle(
            newTracks: Array(fresh.prefix(40)),
            newArtists: newArtists,
            newGenres: newGenres
        )
    }
}
