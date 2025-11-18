import SwiftUI

struct SoundPrintView: View {

    @EnvironmentObject var auth: SpotifyAuthService
    @StateObject private var api = SpotifyAPI()

    @State private var profile: SpotifyUserProfile?
    @State private var topArtists: [SpotifyArtist] = []
    @State private var topTracks: [SpotifyTrack] = []
    @State private var genreStats: [GenreStat] = []
    @State private var personality: FanPersonality?

    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var isExporting = false
    @State private var exportImage: UIImage?

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            if isLoading {
                ProgressView("Loading your SoundPrint…")
                    .foregroundColor(.white)
                    .font(.title3)
            } else if let error = errorMessage {
                errorStateView(error)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        headerSection

                        if !genreStats.isEmpty {
                            genreSection
                        }

                        if !topArtists.isEmpty {
                            topArtistsSection
                        }

                        if !topTracks.isEmpty {
                            topTracksSection
                        }

                        if let p = personality {
                            personalitySection(p)
                        }

                        shareButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
                }
            }
        }
        .task {
            await loadData()
        }
        .sheet(isPresented: $isExporting) {
            if let img = exportImage {
                ShareSheet(items: [img])
            }
        }
    }
}

// MARK: - Background

private extension SoundPrintView {
    var backgroundGradient: LinearGradient {
        LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.05, blue: 0.10),
                    Color(red: 0.10, green: 0.10, blue: 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
    }
}

// MARK: - Sections

private extension SoundPrintView {

    // Error state
    func errorStateView(_ error: String) -> some View {
        VStack(spacing: 14) {
            Text("Something went wrong")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text(error)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Button {
                Task { await loadData() }
            } label: {
                Text("Retry")
                    .bold()
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    // Header (profile + top genre)
    var headerSection: some View {
        VStack(spacing: 16) {
            if let url = profile?.imageURL {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.white.opacity(0.2)
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.yellow.opacity(0.7), lineWidth: 3))
                .shadow(color: .black.opacity(0.5), radius: 16)
            }

            Text(profile?.display_name ?? "Your SoundPrint")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            if let top = genreStats.first {
                Text("Top genre: \(top.genre.capitalized)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.yellow.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
            }

            Text("A dark, rich look at what you’ve really been spinning.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 8)
    }

    // Genres card
    var genreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Genres")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            FlowLayout(
                mode: .vstack,
                items: genreStats,
                itemSpacing: 10,
                rowSpacing: 10
            ) { g in
                Text("\(g.genre.capitalized) • \(Int(g.percent * 100))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.yellow.opacity(0.9))
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // Artists card
    var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Artists")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(topArtists.prefix(10)) { artist in
                        VStack(spacing: 8) {
                            if let url = artist.imageURL {
                                AsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Color.white.opacity(0.2)
                                }
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .shadow(color: .black.opacity(0.5), radius: 10)
                            }

                            Text(artist.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // Tracks card
    var topTracksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top Tracks")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(spacing: 10) {
                ForEach(topTracks.prefix(8)) { track in
                    HStack(spacing: 12) {
                        if let url = track.album?.imageURL {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color.white.opacity(0.2)
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 52, height: 52)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)

                            Text(track.artists.first?.name ?? "")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // Personality card
    func personalitySection(_ p: FanPersonality) -> some View {
        VStack(spacing: 14) {
            Text("Listening Personality")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(p.emoji)
                .font(.system(size: 70))

            Text(p.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(p.description)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.20, blue: 0.55),
                            Color(red: 0.10, green: 0.12, blue: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    func preloadImages(from artists: [SpotifyArtist]) async -> [String: UIImage] {
        var dict: [String: UIImage] = [:]

        for artist in artists.prefix(4) {
            if let url = artist.imageURL {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let img = UIImage(data: data) {
                    dict[artist.id] = img
                }
            }
        }
        return dict
    }

    // Share button
    var shareButton: some View {
        Button {
            Task { await exportCard() }
        } label: {
            Text("Share My SoundPrint")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.yellow)
                .cornerRadius(18)
        }
        .padding(.top, 8)
    }
}

// MARK: - Data Loading & Genres

extension SoundPrintView {

    func loadData() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let p = try await api.getUserProfile()
            let artists = try await api.getTopArtists(limit: 20)
            let tracks = try await api.getTopTracks(limit: 20)

            let genres = computeGenres(from: artists)
            let personality = FanPersonalityEngine.compute(artists: artists, tracks: tracks)

            await MainActor.run {
                self.profile = p
                self.topArtists = artists
                self.topTracks = tracks
                self.genreStats = genres
                self.personality = personality
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Image preloading for export

    func preloadProfileImage(from profile: SpotifyUserProfile?) async -> UIImage? {
        guard let url = profile?.imageURL else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            print("Failed to preload profile image:", error)
            return nil
        }
    }

    func preloadArtistImages(from artists: [SpotifyArtist]) async -> [String: UIImage] {
        var dict: [String: UIImage] = [:]

        for artist in artists.prefix(4) {
            guard let url = artist.imageURL else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let img = UIImage(data: data) {
                    dict[artist.id] = img
                }
            } catch {
                print("Failed to preload artist image for \(artist.name):", error)
            }
        }
        return dict
    }

    func preloadAlbumImages(from tracks: [SpotifyTrack]) async -> [String: UIImage] {
        var dict: [String: UIImage] = [:]

        for track in tracks.prefix(6) {
            if let album = track.album,                      // <-- unwrap safely
               let url = album.imageURL {

                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let img = UIImage(data: data) {
                        dict[track.id] = img
                    }
                } catch {
                    print("Failed to preload album image for \(track.name):", error)
                }
            }
        }

        return dict
    }

    /// Build GenreStat list from artists' genres.
    func computeGenres(from artists: [SpotifyArtist]) -> [GenreStat] {
        var counts: [String: Int] = [:]

        for artist in artists {
            for g in (artist.genres ?? []) { // genres is [String]? in your models
                let key = g
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard !key.isEmpty else { continue }
                counts[key, default: 0] += 1
            }
        }

        let total = Double(counts.values.reduce(0, +))
        guard total > 0 else { return [] }

        return counts
            .map { (genre: $0.key, percent: Double($0.value) / total) }
            .sorted { $0.percent > $1.percent }
            .map { GenreStat(genre: $0.genre, percent: $0.percent) }
    }
}

// MARK: - Export

extension SoundPrintView {

    @MainActor
        func exportCard() async {
            // 1. Preload images off the network
            let profileImg = await preloadProfileImage(from: profile)
            let artistImgs = await preloadArtistImages(from: topArtists)
            let albumImgs  = await preloadAlbumImages(from: topTracks)

            // 2. Build export view with preloaded images
            let exportView = SoundPrintExportCard(
                profile: profile,
                profileImage: profileImg,
                artists: topArtists,
                artistImages: artistImgs,
                tracks: topTracks,
                albumImages: albumImgs,
                genres: genreStats,
                personality: personality
            )

            // 3. Render to PNG
            if let img = await ShareExporter.renderImage(exportView, width: 1080, scale: 3.0) {
                self.exportImage = img
                self.isExporting = true
            }
        }
}
