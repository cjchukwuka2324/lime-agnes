import SwiftUI

struct SoundPrintView: View {

    @EnvironmentObject var authService: SpotifyAuthService
    @StateObject private var api = SpotifyAPI()

    // MARK: - Loaded data
    @State private var profile: SpotifyUserProfile?
    @State private var topArtists: [SpotifyArtist] = []
    @State private var topTracks: [SpotifyTrack] = []
    @State private var genreStats: [GenreStat] = []
    @State private var personality: FanPersonality?

    // MARK: - Insights
    @State private var realYou: RealYouMix?
    @State private var forecast: SoundprintForecast?
    @State private var discovery: DiscoveryBundle?

    @State private var isLoading = true
    @State private var errorMessage: String?

    private var discoveryEngine: DiscoveryEngine {
        DiscoveryEngine(api: api)
    }

    var body: some View {
        NavigationStack {
            ZStack {

                // =====================================================
                // MARK: - STRONG MULTI-PASS SPOTIFY GRADIENT BACKGROUND
                // =====================================================
                LinearGradient(
                    colors: [
                        Color(hex: "#050505"), // near-black
                        Color(hex: "#0C7C38"), // deep green
                        Color(hex: "#1DB954"), // Spotify green
                        Color(hex: "#1ED760"), // bright lime
                        Color(hex: "#050505")  // back to near-black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Optional subtle vignette
                RadialGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.6)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 600
                )
                .ignoresSafeArea()

                // =====================================================
                // MARK: - CONTENT
                // =====================================================
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Loading your SoundPrint…")
                            .foregroundColor(.white)
                    }

                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .padding()

                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 32) {

                            // SOLID ANIMATED PILL HEADER
                            heroHeader

                            // TOP GENRES
                            if !genreStats.isEmpty {
                                genreSection()
                            }

                            // TOP ARTISTS
                            if !topArtists.isEmpty {
                                topArtistsSection()
                            }

                            // TOP TRACKS
                            if !topTracks.isEmpty {
                                topTracksSection()
                            }

                            // THE REAL YOU
                            if let realYou {
                                realYouSection(realYou)
                            }

                            // FORECAST
                            if let forecast {
                                forecastSection(forecast)
                            }

                            // DISCOVERY
                            if let discovery {
                                discoverySection(discovery)
                            }

                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await loadData()
                await loadInsights()
            }
        }
    }

    // =====================================================
    // MARK: - HERO HEADER (Animated Pill Gradient)
    // =====================================================
    private var heroHeader: some View {
        ZStack {
            // Glow behind the pill
            RoundedRectangle(cornerRadius: 40)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1ED760").opacity(0.4),
                            Color(hex: "#1DB954").opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blur(radius: 30)
                .scaleEffect(1.1)

            VStack(spacing: 8) {
                Text("SOUNDPRINT")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(.white)
                    .kerning(1.2)

                Text("Your Music Identity")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                // Animated waveform inside the pill
                AnimatedWaveformView()
                    .padding(.top, 4)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#1ED760"),
                        Color(hex: "#1DB954"),
                        Color(hex: "#109C4B")
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
        }
        .shadow(color: Color.black.opacity(0.55), radius: 22, x: 0, y: 14)
        .padding(.top, 28)
    }

    // =====================================================
    // MARK: - LOAD BASE DATA
    // =====================================================

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
            let pers = FanPersonalityEngine.compute(artists: artists, tracks: tracks)

            await MainActor.run {
                self.profile = p
                self.topArtists = artists
                self.topTracks = tracks
                self.genreStats = genres
                self.personality = pers
                self.isLoading = false
            }

        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // =====================================================
    // MARK: - LOAD INSIGHTS
    // =====================================================

    func loadInsights() async {
        guard !genreStats.isEmpty,
              !topArtists.isEmpty,
              !topTracks.isEmpty else { return }

        do {
            async let r = discoveryEngine.buildRealYouMix(
                genres: genreStats,
                topArtists: topArtists,
                topTracks: topTracks
            )
            async let f = discoveryEngine.buildForecast(
                genres: genreStats,
                topArtists: topArtists,
                topTracks: topTracks
            )
            async let d = discoveryEngine.buildDiscoveryBundle(
                genres: genreStats,
                topArtists: topArtists,
                topTracks: topTracks
            )

            let (rOut, fOut, dOut) = try await (r, f, d)

            await MainActor.run {
                self.realYou = rOut
                self.forecast = fOut
                self.discovery = dOut
            }

        } catch {
            print("Discovery / insights error:", error)
        }
    }

    // =====================================================
    // MARK: - GENRE COMPUTATION
    // =====================================================

    func computeGenres(from artists: [SpotifyArtist]) -> [GenreStat] {
        var counts: [String: Int] = [:]

        for artist in artists {
            for g in artist.genres ?? [] {
                let key = g.lowercased()
                counts[key, default: 0] += 1
            }
        }

        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }

        let stats = counts.map { (genre, count) in
            GenreStat(
                genre: genre,
                percent: Double(count) / Double(total)
            )
        }

        return stats.sorted { $0.percent > $1.percent }
    }

    // =====================================================
    // MARK: - SECTIONS
    // =====================================================

    @ViewBuilder
    func genreSection() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Top Genres")

            FlowLayout(
                mode: .vstack,
                items: genreStats,
                itemSpacing: 12,
                rowSpacing: 12
            ) { g in
                Text("\(g.genre.capitalized) • \(Int(g.percent * 100))%")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    func topArtistsSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Top Artists")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(topArtists.prefix(10)) { artist in
                        VStack {
                            AsyncImage(url: artist.imageURL) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.2))
                            }
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text(artist.name)
                                .font(.footnote)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func topTracksSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Top Tracks")

            ForEach(topTracks.prefix(8)) { track in
                HStack(spacing: 12) {
                    AsyncImage(url: track.album?.imageURL) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.2))
                    }
                    .frame(width: 55, height: 55)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(track.name)
                        .foregroundColor(.white)
                        .font(.body)
                        .lineLimit(1)

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    func realYouSection(_ mix: RealYouMix) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("🔥 The Real You")

            Text(mix.subtitle)
                .foregroundColor(.white.opacity(0.9))
                .font(.subheadline)

            Text(mix.description)
                .foregroundColor(.white.opacity(0.8))
                .font(.footnote)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(mix.tracks.prefix(10)) { track in
                        VStack {
                            AsyncImage(url: track.album?.imageURL) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.4))
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            Text(track.name)
                                .foregroundColor(.white)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func forecastSection(_ f: SoundprintForecast) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("🔮 Your 2025 Soundprint Forecast")

            Text(f.headline)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))

            if !f.risingGenres.isEmpty {
                Text("Rising Genres")
                    .foregroundColor(.yellow)
                    .font(.headline)

                ForEach(f.risingGenres.prefix(5), id: \.self) { g in
                    Text("• \(g.genre.capitalized) (\(Int(g.percent * 100))%)")
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            if !f.suggestedTracks.isEmpty {
                Text("Suggested Tracks")
                    .font(.headline)
                    .foregroundColor(.yellow)
                    .padding(.top, 8)

                ForEach(f.suggestedTracks.prefix(5)) { track in
                    Text("• \(track.name)")
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }

    @ViewBuilder
    func discoverySection(_ d: DiscoveryBundle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("🧭 For You — New Discoveries")

            if !d.newArtists.isEmpty {
                Text("New Artists You Might Love")
                    .font(.headline)
                    .foregroundColor(.yellow)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(d.newArtists.prefix(10)) { artist in
                            VStack {
                                AsyncImage(url: artist.imageURL) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.3))
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                Text(artist.name)
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            if !d.newTracks.isEmpty {
                Text("New Tracks For You")
                    .font(.headline)
                    .foregroundColor(.yellow)

                ForEach(d.newTracks.prefix(8)) { track in
                    Text("• \(track.name)")
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            if !d.newGenres.isEmpty {
                Text("New Genres to Explore")
                    .font(.headline)
                    .foregroundColor(.yellow)

                ForEach(d.newGenres.prefix(8), id: \.self) { g in
                    Text("• \(g.capitalized)")
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
    }

    // =====================================================
    // MARK: - Helpers
    // =====================================================

    func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title2.bold())
            .foregroundColor(.white)
            .padding(.bottom, 4)
    }
}

// =====================================================
// MARK: - Animated Waveform View
// =====================================================
private struct AnimatedWaveformView: View {
    @State private var phase: Double = 0
    private let barCount = 28

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let normalized = (sin(phase + Double(index) / 3.0) + 1) / 2 // 0...1
                let height = 6 + normalized * 20

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.35 + normalized * 0.65))
                    .frame(width: 3, height: height)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                phase = 2 * .pi
            }
        }
    }
}

// =====================================================
// MARK: - HEX Color Support
// =====================================================
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255,
                            (int >> 8) * 17,
                            (int >> 4 & 0xF) * 17,
                            (int & 0xF) * 17)

        case 6: // RGB (24-bit)
            (a, r, g, b) = (255,
                            int >> 16,
                            int >> 8 & 0xFF,
                            int & 0xFF)

        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24,
                            int >> 16 & 0xFF,
                            int >> 8 & 0xFF,
                            int & 0xFF)

        default:
            (a, r, g, b) = (255, 0, 255, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}gi
