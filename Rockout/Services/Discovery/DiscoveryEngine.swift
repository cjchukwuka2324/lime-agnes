import Foundation

// MARK: - Data Models

struct RealYouMix {
    let title: String
    let subtitle: String
    let description: String
    let genres: [GenreStat]
    let tracks: [UnifiedTrack]
    
    init(title: String, subtitle: String, description: String, genres: [GenreStat], tracks: [UnifiedTrack]) {
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
    let suggestedTracks: [UnifiedTrack]
    
    init(headline: String, risingGenres: [GenreStat], wildcardGenres: [GenreStat], suggestedTracks: [UnifiedTrack]) {
        self.headline = headline
        self.risingGenres = risingGenres
        self.wildcardGenres = wildcardGenres
        self.suggestedTracks = suggestedTracks
    }
}

struct DiscoveryBundle {
    let newTracks: [UnifiedTrack]
    let newArtists: [UnifiedArtist]
    let newGenres: [String]
    
    init(newTracks: [UnifiedTrack], newArtists: [UnifiedArtist], newGenres: [String]) {
        self.newTracks = newTracks
        self.newArtists = newArtists
        self.newGenres = newGenres
    }
}

// MARK: - New Playlist Models

struct MoreFromYourFaves {
    let tracks: [UnifiedTrack]
}

struct GenreDive {
    let genre: String
    let tracks: [UnifiedTrack]
    let description: String
}

struct ThrowbackDiscovery {
    let tracks: [UnifiedTrack]
    let description: String
}

// MARK: - Discovery Engine

final class DiscoveryEngine {

    private let api: SpotifyAPI

    init(api: SpotifyAPI) {
        self.api = api
    }

    // MARK: - 1. The Real You Mix
    /// Uses actual listening history to identify tracks users love and replay
    func buildRealYouMix(
        genres: [GenreStat],
        topArtists: [SpotifyArtist],
        topTracks: [SpotifyTrack],
        playHistory: [ListeningStatsService.PlayHistoryItem]? = nil
    ) async throws -> RealYouMix {

        guard !topTracks.isEmpty else {
            throw NSError(domain: "DiscoveryEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No top tracks available"])
        }

        let sortedGenres = genres.sorted { $0.percent > $1.percent }
        let coreGenres = Array(sortedGenres.prefix(3))

        // If we have play history, use it to find truly loved tracks
        var lovedTrackIds: [String] = []
        var favoriteArtistIds: [String] = []
        
        if let playHistory = playHistory {
            // Count plays per track to find most replayed
            var trackPlayCounts: [String: Int] = [:]
            var artistPlayCounts: [String: Int] = [:]
            
            for item in playHistory {
                trackPlayCounts[item.trackId, default: 0] += 1
                for artistId in item.artistIds {
                    artistPlayCounts[artistId, default: 0] += 1
                }
            }
            
            // Get tracks with multiple plays (loved tracks)
            lovedTrackIds = trackPlayCounts
                .filter { $0.value >= 2 } // Played at least twice
                .sorted { $0.value > $1.value }
                .prefix(20)
                .map { $0.key }
            
            // Get favorite artists based on play counts
            favoriteArtistIds = artistPlayCounts
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { $0.key }
        }
        
        // Use loved tracks for seeds, fallback to top tracks
        let seedTrackIDs = !lovedTrackIds.isEmpty ? 
            Array(lovedTrackIds.prefix(3)) : 
            Array(topTracks.prefix(3)).map { $0.id }
        
        let seedArtistIDs = !favoriteArtistIds.isEmpty ?
            Array(favoriteArtistIds.prefix(2)) :
            Array(topArtists.prefix(2)).map { $0.id }
        
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

        // Playlist composition: 60% loved/replayed tracks, 25% favorite artists, 15% new recommendations
        let lovedTracksCount = min(18, lovedTrackIds.count)
        let favoriteArtistsCount = 7
        let recCount = 5

        // Get loved tracks from topTracks if available
        var mainTracks: [SpotifyTrack] = []
        if !lovedTrackIds.isEmpty {
            let lovedTracks = topTracks.filter { lovedTrackIds.contains($0.id) }
            mainTracks.append(contentsOf: Array(lovedTracks.prefix(lovedTracksCount)))
        }
        
        // Add tracks from favorite artists
        let favoriteArtists = topArtists.filter { favoriteArtistIds.contains($0.id) }
        let favoriteArtistTrackIds = Set(favoriteArtists.map { $0.id })
        let artistTracks = topTracks.filter { track in
            track.artists.contains { favoriteArtistTrackIds.contains($0.id) } && 
            !lovedTrackIds.contains(track.id)
        }
        mainTracks.append(contentsOf: Array(artistTracks.prefix(favoriteArtistsCount)))
        
        // Fill remaining with top tracks if needed
        if mainTracks.count < 25 {
            let remaining = 25 - mainTracks.count
            let additionalTracks = topTracks.filter { !Set(mainTracks.map { $0.id }).contains($0.id) }
            mainTracks.append(contentsOf: Array(additionalTracks.prefix(remaining)))
        }
        
        let recTracks = Array(recs.prefix(recCount))
        var final = Array(mainTracks.prefix(25)) + recTracks
        
        // Ensure minimum 10 tracks - fill with top tracks if needed
        if final.count < 10 {
            print("⚠️ RealYouMix: Only \(final.count) tracks, filling with top tracks")
            let existingIds = Set(final.map { $0.id })
            let additionalTracks = topTracks.filter { !existingIds.contains($0.id) }
            final.append(contentsOf: Array(additionalTracks.prefix(10 - final.count)))
        }
        
        // Final safety check - ensure we have at least some tracks
        if final.isEmpty {
            print("⚠️ RealYouMix: Final array empty, using top tracks as fallback")
            final = Array(topTracks.prefix(30))
        }

        let desc = "Built from your core: \(coreGenres.first?.genre.capitalized ?? "your sound")."

        return RealYouMix(
            title: "The Real You",
            subtitle: "Your core sound right now",
            description: desc,
            genres: coreGenres,
            tracks: final.map { $0.toUnified() }
        )
    }

    // MARK: - 2. Soundprint Forecast
    /// Uses rising + wildcard genres and mid-tier artists. 100% fresh tracks verified as new.
    func buildForecast(
        genres: [GenreStat],
        topArtists: [SpotifyArtist],
        topTracks: [SpotifyTrack],
        playHistory: [ListeningStatsService.PlayHistoryItem]? = nil
    ) async throws -> SoundprintForecast {

        let sorted = genres.sorted { $0.percent > $1.percent }

        // Wildcards = tiny emerging genres
        let wildcards = sorted.filter { $0.percent > 0 && $0.percent < 0.035 }

        // Rising = mid-tier genre slices
        let rising = sorted.filter { $0.percent >= 0.035 && $0.percent < 0.12 }

        // Get all known track IDs from both top tracks and full listening history
        var knownTrackIDs = Set(topTracks.map { $0.id })
        if let playHistory = playHistory {
            knownTrackIDs.formUnion(Set(playHistory.map { $0.trackId }))
        }

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
                limit: 100 // Get more to filter by release date
            )
        } catch {
            print("⚠️ Forecast fallback: genres only")
            raw = try await api.getRecommendations(
                seedArtists: [],
                seedGenres: seedGenres,
                seedTracks: [],
                limit: 100
            )
        }

        // Filter out known tracks
        var freshTracks = raw.filter { !knownTrackIDs.contains($0.id) }
        
        // Verify tracks are genuinely new (released in last 3-6 months)
        let calendar = Calendar.current
        let now = Date()
        guard let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now),
              let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) else {
            // If date calculation fails, just use fresh tracks
            let finalTracks = Array(freshTracks.prefix(30))
            return SoundprintForecast(
                headline: "Your soundprint is shifting.",
                risingGenres: rising,
                wildcardGenres: wildcards,
                suggestedTracks: finalTracks.map { $0.toUnified() }
            )
        }
        
        // Filter tracks by release date (prioritize last 3-6 months)
        var verifiedNewTracks: [SpotifyTrack] = []
        var olderNewTracks: [SpotifyTrack] = []
        
        for track in freshTracks {
            guard let album = track.album,
                  let releaseDate = album.releaseDate else {
                // If no release date, include it but deprioritize
                olderNewTracks.append(track)
                continue
            }
            
            if releaseDate >= threeMonthsAgo {
                // Very new (last 3 months) - highest priority
                verifiedNewTracks.insert(track, at: 0)
            } else if releaseDate >= sixMonthsAgo {
                // New (3-6 months)
                verifiedNewTracks.append(track)
            } else {
                // Older but still new to user
                olderNewTracks.append(track)
            }
        }
        
        // Prioritize recently released tracks, but include some older discoveries
        let finalTracks = Array((verifiedNewTracks.prefix(25) + olderNewTracks.prefix(5)).prefix(30))

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
            suggestedTracks: finalTracks.map { $0.toUnified() }
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
            newTracks: Array(fresh.prefix(40)).map { $0.toUnified() },
            newArtists: newArtists.map { $0.toUnified() },
            newGenres: newGenres
        )
    }
    
    // MARK: - 4. More from your faves (Deep Cuts)
    /// Lesser-known tracks from user's favorite artists (not their top hits)
    func buildMoreFromYourFaves(
        playHistory: [ListeningStatsService.PlayHistoryItem],
        topArtists: [SpotifyArtist],
        audioFeatures: AverageAudioFeatures?
    ) async throws -> MoreFromYourFaves {
        // Get top 5-10 favorite artists based on play counts
        var artistPlayCounts: [String: Int] = [:]
        for item in playHistory {
            for artistId in item.artistIds {
                artistPlayCounts[artistId, default: 0] += 1
            }
        }
        
        let favoriteArtistIds = artistPlayCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
            .filter { id in topArtists.contains { $0.id == id } }
        
        guard !favoriteArtistIds.isEmpty else {
            throw NSError(domain: "DiscoveryEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No favorite artists found"])
        }
        
        var allDeepCuts: [SpotifyTrack] = []
        let artistsToProcess = Array(favoriteArtistIds.prefix(8)) // Limit to 8 artists
        
        for artistId in artistsToProcess {
            do {
                // Get artist's top tracks to exclude
                let topTracks = try await api.getArtistTopTracks(artistId: artistId)
                let topTrackIds = Set(topTracks.prefix(20).map { $0.id })
                
                // Get all albums
                let albums = try await api.getAllArtistAlbums(artistId: artistId)
                
                // Get tracks from recent albums (last 3-5 albums to avoid too much processing)
                let recentAlbums = Array(albums.prefix(5))
                var artistDeepCuts: [SpotifyTrack] = []
                
                for album in recentAlbums {
                    let albumTracks = try await api.getAlbumTracks(albumId: album.id)
                    // Filter out top tracks and get full track details if needed
                    let deepCuts = albumTracks.filter { !topTrackIds.contains($0.id) }
                    artistDeepCuts.append(contentsOf: deepCuts.prefix(5))
                    
                    if artistDeepCuts.count >= 4 {
                        break // Get 3-5 tracks per artist
                    }
                }
                
                allDeepCuts.append(contentsOf: artistDeepCuts.prefix(4))
            } catch {
                print("⚠️ Failed to get deep cuts for artist \(artistId): \(error.localizedDescription)")
                continue
            }
        }
        
        // Limit total tracks and convert to unified
        let finalTracks = Array(allDeepCuts.prefix(30))
        return MoreFromYourFaves(tracks: finalTracks.map { $0.toUnified() })
    }
    
    // MARK: - 5. Genre Dive
    /// Deep dive into one of user's emerging genres
    func buildGenreDive(
        playHistory: [ListeningStatsService.PlayHistoryItem],
        genreStats: [GenreStat],
        topArtists: [SpotifyArtist]
    ) async throws -> GenreDive {
        let sortedGenres = genreStats.sorted { $0.percent > $1.percent }
        
        // Find emerging genre (3-10% of listening, not the top one)
        let emergingGenre = sortedGenres
            .filter { $0.percent >= 0.03 && $0.percent <= 0.10 }
            .first ?? sortedGenres.dropFirst().first ?? sortedGenres.first!
        
        let genreName = emergingGenre.genre.lowercased()
        
        // Get artists user listens to in this genre
        let genreArtistIds = Set(topArtists.filter { artist in
            artist.genres?.contains { $0.lowercased() == genreName } ?? false
        }.map { $0.id }.prefix(5))
        
        // Get recommendations: 50% from known artists, 50% new
        let seedArtists = Array(genreArtistIds)
        let seedGenres = [genreName]
        
        let knownTrackIds = Set(playHistory.map { $0.trackId })
        
        var recommendations: [SpotifyTrack]
        do {
            recommendations = try await api.getRecommendations(
                seedArtists: seedArtists,
                seedGenres: seedGenres,
                seedTracks: [],
                limit: 40
            )
        } catch {
            // Fallback to genres only
            recommendations = try await api.getRecommendations(
                seedArtists: [],
                seedGenres: seedGenres,
                seedTracks: [],
                limit: 40
            )
        }
        
        // Mix: include some tracks from known artists, some new
        let fromKnownArtists = recommendations.filter { track in
            track.artists.contains { genreArtistIds.contains($0.id) }
        }
        let newTracks = recommendations.filter { track in
            !knownTrackIds.contains(track.id) && !track.artists.contains { genreArtistIds.contains($0.id) }
        }
        
        var finalTracks = Array((fromKnownArtists.prefix(15) + newTracks.prefix(15)).prefix(30))
        
        // Ensure minimum 10 tracks - fill with recommendations if needed
        if finalTracks.count < 10 {
            print("⚠️ GenreDive: Only \(finalTracks.count) tracks, filling with more recommendations")
            let existingIds = Set(finalTracks.map { $0.id })
            let additionalTracks = recommendations.filter { !existingIds.contains($0.id) }
            finalTracks.append(contentsOf: Array(additionalTracks.prefix(10 - finalTracks.count)))
        }
        
        // Final safety check - if still empty or too few, add more recommendations
        if finalTracks.isEmpty {
            print("⚠️ GenreDive: Final array empty, using all recommendations")
            finalTracks = Array(recommendations.prefix(30))
        }
        
        return GenreDive(
            genre: emergingGenre.genre,
            tracks: finalTracks.map { $0.toUnified() },
            description: "A deep dive into \(emergingGenre.genre)"
        )
    }
    
    // MARK: - 6. Throwback Discovery
    /// New releases from artists user used to listen to but hasn't recently
    func buildThrowbackDiscovery(
        playHistory: [ListeningStatsService.PlayHistoryItem],
        topArtists: [SpotifyArtist]
    ) async throws -> ThrowbackDiscovery {
        let calendar = Calendar.current
        let now = Date()
        guard let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now),
              let oneYearAgo = calendar.date(byAdding: .month, value: -12, to: now),
              let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else {
            throw NSError(domain: "DiscoveryEngine", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Date calculation failed"])
        }
        
        // Find artists listened to 6-12 months ago
        var artistPlaysOld: [String: [Date]] = [:]
        var artistPlaysRecent: [String: Int] = [:]
        
        for item in playHistory {
            let playedAt = item.playedAt
            for artistId in item.artistIds {
                if playedAt >= oneYearAgo && playedAt < sixMonthsAgo {
                    // In the throwback period
                    if artistPlaysOld[artistId] == nil {
                        artistPlaysOld[artistId] = []
                    }
                    artistPlaysOld[artistId]?.append(playedAt)
                } else if playedAt >= thirtyDaysAgo {
                    // Recent plays
                    artistPlaysRecent[artistId, default: 0] += 1
                }
            }
        }
        
        // Find artists with old plays but few/no recent plays
        let throwbackArtists = artistPlaysOld.keys.filter { artistId in
            (artistPlaysRecent[artistId] ?? 0) < 3
        }
        
        var newReleases: [SpotifyTrack] = []
        
        // If no throwback artists found, use top artists as fallback
        let artistsToCheck: [String]
        if !throwbackArtists.isEmpty {
            artistsToCheck = Array(throwbackArtists.prefix(10))
        } else {
            print("⚠️ ThrowbackDiscovery: No throwback artists found, using top artists as fallback")
            artistsToCheck = Array(topArtists.prefix(5).map { $0.id })
        }
        
        for artistId in artistsToCheck {
            do {
                // Get recent albums (last 6 months)
                let albums = try await api.getAllArtistAlbums(artistId: artistId)
                let recentAlbums = albums.filter { album in
                    guard let releaseDate = album.releaseDate else { return false }
                    return releaseDate >= sixMonthsAgo
                }
                
                // Get tracks from recent albums
                for album in recentAlbums.prefix(3) {
                    let tracks = try await api.getAlbumTracks(albumId: album.id)
                    newReleases.append(contentsOf: tracks.prefix(3))
                    
                    if newReleases.count >= 30 {
                        break
                    }
                }
                
                if newReleases.count >= 30 {
                    break
                }
            } catch {
                print("⚠️ Failed to get throwback releases for artist \(artistId): \(error.localizedDescription)")
                continue
            }
        }
        
        // Ensure minimum 10 tracks - use top tracks as fallback if needed
        var finalTracks = Array(newReleases.prefix(30))
        
        if finalTracks.count < 10 && !topArtists.isEmpty {
            print("⚠️ ThrowbackDiscovery: Only \(finalTracks.count) tracks, filling with artist top tracks")
            let existingIds = Set(finalTracks.map { $0.id })
            for artistId in artistsToCheck.prefix(5) {
                if finalTracks.count >= 10 { break }
                do {
                    let topTracks = try await api.getArtistTopTracks(artistId: artistId, market: "US")
                    let newTracks = topTracks.filter { !existingIds.contains($0.id) }
                    finalTracks.append(contentsOf: Array(newTracks.prefix(10 - finalTracks.count)))
                } catch {
                    continue
                }
            }
        }
        
        return ThrowbackDiscovery(
            tracks: finalTracks.map { $0.toUnified() },
            description: throwbackArtists.isEmpty ? "Recent releases from your favorite artists" : "New releases from artists you used to love"
        )
    }
    
    // MARK: - 7. Mood Playlists
    /// Generate playlists for different moods based on audio features
    func buildMoodPlaylists(
        playHistory: [ListeningStatsService.PlayHistoryItem],
        topTracks: [SpotifyTrack]
    ) async throws -> [MoodPlaylist] {
        // Get audio features for top tracks
        let trackIds = topTracks.map { $0.id }
        let audioFeaturesDict: [String: AudioFeatures]
        do {
            let features = try await api.getAudioFeatures(trackIds: trackIds)
            audioFeaturesDict = Dictionary(uniqueKeysWithValues: zip(trackIds, features))
        } catch {
            print("⚠️ Failed to get audio features for mood playlists: \(error.localizedDescription)")
            // Return basic mood playlists based on top tracks without audio features
            return [
                MoodPlaylist(
                    mood: "Chill",
                    tracks: Array(topTracks.prefix(20)).map { $0.toUnified() },
                    description: "Your top tracks for relaxing"
                ),
                MoodPlaylist(
                    mood: "Energy",
                    tracks: Array(topTracks.suffix(20)).map { $0.toUnified() },
                    description: "Your top tracks for energy"
                )
            ]
        }
        
        // Map tracks with their features
        let tracksWithFeatures = topTracks.compactMap { track -> (SpotifyTrack, AudioFeatures)? in
            guard let features = audioFeaturesDict[track.id] else { return nil }
            return (track, features)
        }
        
        // Define mood criteria
        let workoutTracks = tracksWithFeatures.filter { _, features in
            (features.energy ?? 0) > 0.7 && (features.tempo ?? 0) > 130 && (features.danceability ?? 0) > 0.7
        }.map { $0.0 }
        
        let chillTracks = tracksWithFeatures.filter { _, features in
            (features.energy ?? 0) < 0.4 && (features.acousticness ?? 0) > 0.5 && (features.tempo ?? 0) < 120
        }.map { $0.0 }
        
        let focusTracks = tracksWithFeatures.filter { _, features in
            (features.instrumentalness ?? 0) > 0.5 && (features.speechiness ?? 0) < 0.1
        }.map { $0.0 }
        
        let sadTracks = tracksWithFeatures.filter { _, features in
            (features.valence ?? 0) < 0.3 && (features.energy ?? 0) < 0.5
        }.map { $0.0 }
        
        let happyTracks = tracksWithFeatures.filter { _, features in
            (features.valence ?? 0) > 0.7 && (features.energy ?? 0) > 0.6
        }.map { $0.0 }
        
        let danceTracks = tracksWithFeatures.filter { _, features in
            (features.danceability ?? 0) > 0.7 && (features.energy ?? 0) > 0.7 && (features.tempo ?? 0) > 120
        }.map { $0.0 }
        
        var moodPlaylists: [MoodPlaylist] = []
        
        if !workoutTracks.isEmpty {
            moodPlaylists.append(MoodPlaylist(
                mood: "Energy Boost",
                tracks: Array(workoutTracks.prefix(25)).map { $0.toUnified() },
                description: "High energy tracks to fuel your workout"
            ))
        }
        
        if !chillTracks.isEmpty {
            moodPlaylists.append(MoodPlaylist(
                mood: "Chill Vibes",
                tracks: Array(chillTracks.prefix(25)).map { $0.toUnified() },
                description: "Relaxing vibes for unwinding"
            ))
        }
        
        if !focusTracks.isEmpty {
            moodPlaylists.append(MoodPlaylist(
                mood: "Focus Mode",
                tracks: Array(focusTracks.prefix(25)).map { $0.toUnified() },
                description: "Music for concentration and focus"
            ))
        }
        
        if !sadTracks.isEmpty {
            moodPlaylists.append(MoodPlaylist(
                mood: "Melancholy",
                tracks: Array(sadTracks.prefix(25)).map { $0.toUnified() },
                description: "Emotional tracks for reflective moments"
            ))
        }
        
        if !happyTracks.isEmpty {
            moodPlaylists.append(MoodPlaylist(
                mood: "Feel Good",
                tracks: Array(happyTracks.prefix(25)).map { $0.toUnified() },
                description: "Upbeat tracks to lift your mood"
            ))
        }
        
        if !danceTracks.isEmpty {
            moodPlaylists.append(MoodPlaylist(
                mood: "Dance Party",
                tracks: Array(danceTracks.prefix(25)).map { $0.toUnified() },
                description: "High energy dance tracks"
            ))
        }
        
        return moodPlaylists
    }
}
