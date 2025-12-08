import SwiftUI
import UIKit

struct SoundPrintView: View {
    @EnvironmentObject var authService: SpotifyAuthService
    @StateObject private var api = SpotifyAPI()
    private let playlistService = SpotifyPlaylistService.shared

    // MARK: - Loaded data
    @State private var profile: SpotifyUserProfile?
    @State private var topArtists: [SpotifyArtist] = []
    @State private var topTracks: [SpotifyTrack] = []
    @State private var genreStats: [GenreStat] = []
    @State private var personality: FanPersonality?
    
    // New feature data
    @State private var listeningStats: ListeningStats?
    @State private var audioFeatures: AverageAudioFeatures?
    @State private var yearInMusic: YearInMusic?
    @State private var monthlyEvolution: [MonthlyEvolution] = []
    @State private var discoverWeekly: DiscoverWeekly?
    @State private var releaseRadar: ReleaseRadar?
    @State private var recentlyDiscovered: [RecentlyDiscovered] = []
    @State private var moodPlaylists: [MoodPlaylist] = []
    @State private var timePatterns: [TimePattern] = []
    @State private var seasonalTrends: [SeasonalTrend] = []
    @State private var diversity: MusicTasteDiversity?
    @State private var tasteCompatibility: [TasteCompatibility] = []
    
    // Custom curated playlists
    @State private var realYouMix: RealYouMix?
    @State private var soundprintForecast: SoundprintForecast?
    @State private var discoveryBundle: DiscoveryBundle?

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab: Int = 0
    @State private var isAddingToSpotify = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Solid black background
                Color.black
                .ignoresSafeArea()

                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if !authService.isAuthorized() {
                    connectPromptView
                } else {
                    contentView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                await loadData()
            }
        }
    }
    
    // MARK: - Content View
    private var contentView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero Header
                heroHeader
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                
                // Tab Selector
                tabSelector
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                
                // Content based on selected tab
                tabContent
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Hero Header
    private var heroHeader: some View {
        VStack(spacing: 16) {
            // Profile Image or Icon
        ZStack {
                Circle()
                .fill(
                    LinearGradient(
                        colors: [
                                Color(red: 0.12, green: 0.72, blue: 0.33),
                                Color(red: 0.18, green: 0.80, blue: 0.44)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: Color(red: 0.12, green: 0.72, blue: 0.33).opacity(0.5), radius: 20, x: 0, y: 10)
                
                if let imageURL = profile?.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            }
            
            // Name
            Text(profile?.display_name ?? "Your SoundPrint")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            
            // Subtitle
            Text("Your Musical Identity")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            // Personality Badge
            if let personality = personality {
                personalityBadge(personality)
                    .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                TabButton(title: "Overview", icon: "chart.bar.fill", isSelected: selectedTab == 0) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 0
                    }
                }
                TabButton(title: "Artists", icon: "music.mic", isSelected: selectedTab == 1) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 1
                    }
                }
                TabButton(title: "Tracks", icon: "music.note.list", isSelected: selectedTab == 2) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 2
                    }
                }
                TabButton(title: "Genres", icon: "tag.fill", isSelected: selectedTab == 3) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 3
                    }
                }
                TabButton(title: "Stats", icon: "chart.line.uptrend.xyaxis", isSelected: selectedTab == 4) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 4
                    }
                }
                TabButton(title: "Time", icon: "calendar", isSelected: selectedTab == 5) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 5
                    }
                }
                TabButton(title: "Discover", icon: "sparkles", isSelected: selectedTab == 6) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 6
                    }
                }
                TabButton(title: "Social", icon: "person.2.fill", isSelected: selectedTab == 7) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 7
                    }
                }
                TabButton(title: "Mood", icon: "heart.fill", isSelected: selectedTab == 8) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 8
                    }
                }
                TabButton(title: "Analytics", icon: "chart.bar.xaxis", isSelected: selectedTab == 9) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 9
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Overview Tab
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            overviewTab
        case 1:
            artistsTab
        case 2:
            tracksTab
        case 3:
            genresTab
        case 4:
            if let stats = listeningStats, let features = audioFeatures {
                ListeningStatsView(stats: stats, audioFeatures: features)
            } else {
                loadingPlaceholder
            }
        case 5:
            TimeAnalysisView(yearInMusic: yearInMusic, monthlyEvolution: monthlyEvolution)
        case 6:
            DiscoveryView(
                discoverWeekly: discoverWeekly,
                releaseRadar: releaseRadar,
                recentlyDiscovered: recentlyDiscovered,
                realYouMix: realYouMix,
                soundprintForecast: soundprintForecast,
                discoveryBundle: discoveryBundle,
                onOpenInSpotify: handleOpenInSpotify,
                onOpenPlaylist: handleOpenInSpotify
            )
        case 7:
            SocialSharingView(
                profile: profile,
                topArtists: topArtists,
                topTracks: topTracks,
                personality: personality,
                compatibility: tasteCompatibility.isEmpty ? nil : tasteCompatibility
            )
        case 8:
            MoodContextView(
                moodPlaylists: moodPlaylists,
                timePatterns: timePatterns,
                seasonalTrends: seasonalTrends
            )
        case 9:
            if let diversity = diversity, let features = audioFeatures {
                AdvancedAnalyticsView(diversity: diversity, audioFeatures: features)
            } else {
                loadingPlaceholder
            }
        default:
            overviewTab
        }
    }
    
    private var overviewTab: some View {
        VStack(spacing: 20) {
            statsCardsSection
            
            if !topArtists.isEmpty {
                topArtistsPreviewSection
            }
            
            if !topTracks.isEmpty {
                topTracksPreviewSection
            }
        }
    }
    
    private var statsCardsSection: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Top Artists",
                value: "\(topArtists.count)",
                icon: "music.mic",
                color: Color(red: 0.12, green: 0.72, blue: 0.33)
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    selectedTab = 1 // Navigate to Artists tab
                }
            }
            StatCard(
                title: "Top Tracks",
                value: "\(topTracks.count)",
                icon: "music.note.list",
                color: Color(red: 0.18, green: 0.80, blue: 0.44)
            )
        }
    }
    
    private var topTracksPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Tracks")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            ForEach(Array(topTracks.prefix(3).enumerated()), id: \.element.id) { index, track in
                SoundPrintTrackRow(track: track, rank: index + 1)
            }
        }
        .padding(20)
        .background(glassBackgroundStyle)
    }
    
    private var glassBackgroundStyle: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.1))
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }
    
    // MARK: - Artists Tab
    private var artistsTab: some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(topArtists.enumerated()), id: \.element.id) { index, artist in
                NavigationLink {
                    RockListView(artistId: artist.id)
                } label: {
                    ArtistCard(artist: artist, rank: index + 1)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Helper Views
    
    private var topArtistsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Artists")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 1 // Navigate to Artists tab
                    }
                } label: {
                    Text("See All")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                }
            }
            
            ForEach(Array(topArtists.prefix(5).enumerated()), id: \.element.id) { index, artist in
                NavigationLink {
                    RockListView(artistId: artist.id)
                } label: {
                    ArtistRow(artist: artist, rank: index + 1)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(20)
        .background(glassBackgroundStyle)
    }
    
    // MARK: - Tracks Tab
    private var tracksTab: some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(topTracks.enumerated()), id: \.element.id) { index, track in
                TrackCard(track: track, rank: index + 1)
            }
        }
    }
    
    // MARK: - Genres Tab
    private var genresTab: some View {
        VStack(spacing: 20) {
            ForEach(Array(genreStats.prefix(10)), id: \.genre) { stat in
                GenreBar(genre: stat.genre, percentage: stat.percent)
            }
        }
    }
    
    // MARK: - Connect Prompt
    private var connectPromptView: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
            
            Text("Connect Your Spotify")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text("Connect to view your personalized SoundPrint")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(Color(red: 0.12, green: 0.72, blue: 0.33))
                .scaleEffect(1.5)
            
            Text("Loading your SoundPrint...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    // MARK: - Error View
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)
            
            Text("Error")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Personality Badge
    private func personalityBadge(_ personality: FanPersonality) -> some View {
        Text(personality.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                LinearGradient(
                    colors: [
                                Color(red: 0.12, green: 0.72, blue: 0.33),
                                Color(red: 0.18, green: 0.80, blue: 0.44)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            )
    }

    // MARK: - Load Data
    func loadData() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        guard authService.isAuthorized() else {
            await MainActor.run {
                isLoading = false
            }
            return
        }

        do {
            // Load basic data
            let p = try await api.getUserProfile()
            let artistsResponse = try await api.getTopArtists(limit: 20)
            let tracksResponse = try await api.getTopTracks(limit: 20)
            let artists = artistsResponse.items
            let tracks = tracksResponse.items
            let genres = computeGenres(from: artists)
            let pers = FanPersonalityEngine.compute(artists: artists, tracks: tracks)
            
            // Load extended features (with error handling - don't fail if these don't work)
            async let statsTask = loadListeningStats()
            async let featuresTask = loadAudioFeatures(tracks: tracks)
            async let timeTask = loadTimeAnalysis()
            async let discoveryTask = loadDiscovery()
            async let moodTask = loadMoodData(tracks: tracks)
            async let analyticsTask = loadAnalytics(artists: artists, tracks: tracks)

            await MainActor.run {
                self.profile = p
                self.topArtists = artists
                self.topTracks = tracks
                self.genreStats = genres
                self.personality = pers
            }
            
            // Load RockList data for all artists (non-blocking)
            Task {
                await ensureRockListDataForArtists(artists)
            }
            
            // Load extended data (non-blocking)
            _ = try? await statsTask
            _ = try? await featuresTask
            _ = try? await timeTask
            _ = try? await discoveryTask
            _ = try? await moodTask
            _ = try? await analyticsTask
            
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // MARK: - RockList Data Loading
    
    private func ensureRockListDataForArtists(_ artists: [SpotifyArtist]) async {
        // Only proceed if Spotify is authorized
        guard authService.isAuthorized() else {
            print("ℹ️ SoundPrint: Spotify not authorized, skipping RockList data ingestion")
            return
        }
        
        let rockListDataService = RockListDataService.shared
        
        // Ensure RockList data ingestion happens once (not per artist)
        // The ingestion process is global and will process all artists
        do {
            // Check if we need to perform initial ingestion
            print("🔍 SoundPrint: Checking RockList ingestion status...")
            let lastIngested = try? await rockListDataService.getLastIngestedTimestamp()
            
            if lastIngested == nil {
                // Perform initial bootstrap ingestion for all artists
                print("🚀 SoundPrint: No previous ingestion found. Starting initial RockList data ingestion...")
                print("📊 SoundPrint: Will ingest data for \(artists.count) artists")
                try await rockListDataService.performInitialBootstrapIngestion()
                print("✅ SoundPrint: Initial RockList data ingestion completed successfully")
                print("ℹ️ SoundPrint: Backend will process ingested data to calculate RockList rankings")
                print("⏳ SoundPrint: RockList data may take a few moments to be available")
            } else {
                // Perform incremental ingestion for recent plays
                print("🔄 SoundPrint: Previous ingestion found at \(lastIngested?.description ?? "unknown"). Performing incremental update...")
                try await rockListDataService.performIncrementalIngestion(lastIngestedAt: lastIngested)
                print("✅ SoundPrint: Incremental RockList data ingestion completed successfully")
            }
        } catch {
            // Handle different types of errors gracefully
            if let nsError = error as NSError? {
                if nsError.domain == "SpotifyAPI" && nsError.code == 403 {
                    // 403 Forbidden - user needs to reauthorize with new scope
                    print("ℹ️ SoundPrint: Spotify access denied. User may need to reconnect Spotify in Profile settings to grant 'recently played' permission.")
                } else if nsError.domain == "SpotifyAPI" && nsError.code == 401 {
                    // 401 Unauthorized - token expired or invalid
                    print("ℹ️ SoundPrint: Spotify authentication expired. User may need to reconnect Spotify.")
                } else {
                    // Other errors - log detailed information
                    print("⚠️ SoundPrint: Failed to ensure RockList data ingestion")
                    print("⚠️ Error: \(error.localizedDescription)")
                    print("⚠️ Error domain: \(nsError.domain), code: \(nsError.code)")
                    if !nsError.userInfo.isEmpty {
                        print("⚠️ Error userInfo: \(nsError.userInfo)")
                    }
                }
            } else {
                // Unknown error type
                print("⚠️ SoundPrint: Failed to ensure RockList data ingestion: \(error.localizedDescription)")
            }
            // Don't fail the entire load - RockList data calculation is non-critical
        }
    }
    
    // MARK: - Extended Data Loading
    private func loadListeningStats() async throws {
        // Use existing top tracks to calculate stats
        let estimatedMinutes = topTracks.count * 3
        let stats = ListeningStats(
            totalListeningTimeMinutes: estimatedMinutes,
            currentStreak: 7, // Placeholder
            longestStreak: 30, // Placeholder
            mostActiveDay: "Monday",
            mostActiveHour: 20,
            songsDiscoveredThisMonth: 5, // Placeholder
            artistsDiscoveredThisMonth: 3, // Placeholder
            totalSongsPlayed: topTracks.count,
            totalArtistsListened: Set(topArtists.map { $0.id }).count
        )
        
        // Use placeholder audio features for now
        // Will be replaced when extension methods are fully implemented
        let features = AverageAudioFeatures(
            danceability: 0.6, energy: 0.7, valence: 0.65, tempo: 125,
            acousticness: 0.3, instrumentalness: 0.2, liveness: 0.15, speechiness: 0.05
        )
        
        await MainActor.run {
            self.listeningStats = stats
            self.audioFeatures = features
        }
    }
    
    private func loadAudioFeatures(tracks: [SpotifyTrack]) async throws {
        // Use placeholder for now
        let features = AverageAudioFeatures(
            danceability: 0.6, energy: 0.7, valence: 0.65, tempo: 125,
            acousticness: 0.3, instrumentalness: 0.2, liveness: 0.15, speechiness: 0.05
        )
        await MainActor.run {
            self.audioFeatures = features
        }
    }
    
    private func loadTimeAnalysis() async throws {
        // Placeholder - would need historical data
        await MainActor.run {
            self.yearInMusic = YearInMusic(
                year: Calendar.current.component(.year, from: Date()),
                totalListeningTimeMinutes: listeningStats?.totalListeningTimeMinutes ?? 0,
                topGenres: genreStats.prefix(5).map { $0.genre },
                topArtists: topArtists.prefix(5).map { $0.name },
                topTracks: topTracks.prefix(5).map { $0.name },
                favoriteDecade: "2020s",
                mostPlayedMonth: "January"
            )
            self.monthlyEvolution = []
        }
    }
    
    private func loadDiscovery() async throws {
        // Load Spotify's native playlists
        do {
            // Find Discover Weekly
            if let discoverWeeklyPlaylist = try await api.findDiscoverWeekly() {
                let tracks = try await api.getAllPlaylistTracks(playlistId: discoverWeeklyPlaylist.id)
                await MainActor.run {
                    self.discoverWeekly = DiscoverWeekly(tracks: tracks, updatedAt: Date(), playlistId: discoverWeeklyPlaylist.id)
                }
            } else {
                await MainActor.run {
                    self.discoverWeekly = DiscoverWeekly(tracks: [], updatedAt: Date(), playlistId: nil)
                }
            }
            
            // Find Release Radar
            if let releaseRadarPlaylist = try await api.findReleaseRadar() {
                let tracks = try await api.getAllPlaylistTracks(playlistId: releaseRadarPlaylist.id)
                await MainActor.run {
                    self.releaseRadar = ReleaseRadar(tracks: tracks, updatedAt: Date(), playlistId: releaseRadarPlaylist.id)
                }
            } else {
                await MainActor.run {
                    self.releaseRadar = ReleaseRadar(tracks: [], updatedAt: Date(), playlistId: nil)
                }
            }
        } catch {
            // If fetching fails, set empty playlists
            await MainActor.run {
                self.discoverWeekly = DiscoverWeekly(tracks: [], updatedAt: Date(), playlistId: nil)
                self.releaseRadar = ReleaseRadar(tracks: [], updatedAt: Date(), playlistId: nil)
            }
            print("⚠️ Failed to load Spotify playlists: \(error.localizedDescription)")
        }
        
        await MainActor.run {
            self.recentlyDiscovered = [] // Would need to track discovery dates
        }
        
        // Build custom curated playlists
        let discoveryEngine = DiscoveryEngine(api: api)
        
        // Build Real You Mix
        do {
            let realYou = try await discoveryEngine.buildRealYouMix(
                genres: genreStats,
                topArtists: topArtists,
                topTracks: topTracks
            )
            await MainActor.run {
                self.realYouMix = realYou
            }
            print("✅ Real You Mix built: \(realYou.tracks.count) tracks")
        } catch {
            print("⚠️ Failed to build Real You Mix: \(error.localizedDescription)")
            await MainActor.run {
                self.realYouMix = nil
            }
        }
        
        // Build Soundprint Forecast - MUST succeed (has fallbacks built in)
        do {
            let forecast = try await discoveryEngine.buildForecast(
                genres: genreStats,
                topArtists: topArtists,
                topTracks: topTracks
            )
            await MainActor.run {
                self.soundprintForecast = forecast
            }
            print("✅ Soundprint Forecast built: \(forecast.suggestedTracks.count) tracks")
            
            // Validate it has tracks
            if forecast.suggestedTracks.isEmpty {
                print("❌ ERROR: Soundprint Forecast is empty after building!")
            }
        } catch {
            print("❌ CRITICAL: Failed to build Soundprint Forecast: \(error.localizedDescription)")
            // Even if it fails, try to create a minimal forecast with fallback tracks
            if !topTracks.isEmpty {
                let midPoint = max(10, topTracks.count / 3)
                let fallbackTracks = Array(topTracks[midPoint..<min(midPoint + 30, topTracks.count)])
                let fallbackForecast = SoundprintForecast(
                    headline: "Your future sound is evolving.",
                    risingGenres: [],
                    wildcardGenres: [],
                    suggestedTracks: fallbackTracks
                )
                await MainActor.run {
                    self.soundprintForecast = fallbackForecast
                }
                print("✅ Created fallback Soundprint Forecast with \(fallbackTracks.count) tracks")
            } else {
                await MainActor.run {
                    self.soundprintForecast = nil
                }
            }
        }
        
        // Build Discovery Bundle
        do {
            let bundle = try await discoveryEngine.buildDiscoveryBundle(
                genres: genreStats,
                topArtists: topArtists,
                topTracks: topTracks
            )
            await MainActor.run {
                self.discoveryBundle = bundle
            }
            print("✅ Discovery Bundle built: \(bundle.newTracks.count) tracks")
        } catch {
            print("⚠️ Failed to build Discovery Bundle: \(error.localizedDescription)")
            await MainActor.run {
                self.discoveryBundle = nil
            }
        }
    }
    
    private func loadMoodData(tracks: [SpotifyTrack]) async throws {
        // Generate mood playlists based on audio features
        // This is a simplified version
        await MainActor.run {
            self.moodPlaylists = generateMoodPlaylists(from: tracks)
            self.timePatterns = generateTimePatterns()
            self.seasonalTrends = []
        }
    }
    
    private func loadAnalytics(artists: [SpotifyArtist], tracks: [SpotifyTrack]) async throws {
        let diversity = MusicTasteDiversity(
            score: calculateDiversityScore(artists: artists, tracks: tracks),
            genreCount: genreStats.count,
            artistCount: artists.count,
            explorationDepth: Double(genreStats.count) / 10.0 * 100
        )
        await MainActor.run {
            self.diversity = diversity
        }
    }
    
    // MARK: - Helper Functions
    private func generateMoodPlaylists(from tracks: [SpotifyTrack]) -> [MoodPlaylist] {
        // Simplified mood playlist generation
        return [
            MoodPlaylist(mood: "Chill", tracks: Array(tracks.prefix(10)), description: "Relaxing vibes"),
            MoodPlaylist(mood: "Energy", tracks: Array(tracks.suffix(10)), description: "High energy tracks"),
            MoodPlaylist(mood: "Focus", tracks: Array(tracks.prefix(15)), description: "Music for concentration")
        ]
    }
    
    private func generateTimePatterns() -> [TimePattern] {
        // Generate sample time patterns
        return (0..<24).map { hour in
            TimePattern(
                hour: hour,
                playCount: Int.random(in: 10...100),
                dominantGenre: genreStats.first?.genre ?? "Pop"
            )
        }
    }
    
    private func calculateDiversityScore(artists: [SpotifyArtist], tracks: [SpotifyTrack]) -> Double {
        // Simple diversity calculation
        let uniqueGenres = Set(genreStats.map { $0.genre })
        let genreScore = min(Double(uniqueGenres.count) / 20.0 * 50, 50)
        let artistScore = min(Double(artists.count) / 50.0 * 50, 50)
        return genreScore + artistScore
    }
    
    private func handleOpenInSpotify(playlistName: String, tracks: [SpotifyTrack]) {
        Task {
            await MainActor.run {
                isAddingToSpotify = true
            }
            
            do {
                // Create the playlist first
                let trackUris = tracks.map { track in
                    "spotify:track:\(track.id)"
                }
                
                let playlistId = try await playlistService.createPlaylistAndAddTracks(
                    name: playlistName,
                    description: "Curated by Rockout SoundPrint",
                    trackUris: trackUris,
                    isPublic: false
                )
                
                // Open in Spotify app
                await MainActor.run {
                    isAddingToSpotify = false
                    if let spotifyURL = URL(string: "spotify:playlist:\(playlistId)") {
                        if UIApplication.shared.canOpenURL(spotifyURL) {
                            UIApplication.shared.open(spotifyURL)
                        } else if let webURL = URL(string: "https://open.spotify.com/playlist/\(playlistId)") {
                            UIApplication.shared.open(webURL)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isAddingToSpotify = false
                    errorMessage = "Failed to open in Spotify: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func handleOpenInSpotify(playlistId: String) {
        Task {
            await MainActor.run {
                if let spotifyURL = URL(string: "spotify:playlist:\(playlistId)") {
                    if UIApplication.shared.canOpenURL(spotifyURL) {
                        UIApplication.shared.open(spotifyURL)
                    } else if let webURL = URL(string: "https://open.spotify.com/playlist/\(playlistId)") {
                        UIApplication.shared.open(webURL)
                    }
                }
            }
        }
    }
    
    private var loadingPlaceholder: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text("Loading...")
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

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
            GenreStat(genre: genre, percent: Double(count) / Double(total))
        }
        return stats.sorted { $0.percent > $1.percent }
    }
}

// MARK: - Supporting Views

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(isSelected ? Color(red: 0.12, green: 0.72, blue: 0.33) : Color.white.opacity(0.1))
            )
            }
        }
    }

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
        }
    }

struct ArtistRow: View {
    let artist: SpotifyArtist
    let rank: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                .frame(width: 30)
            
            // Artist Image
            AsyncImage(url: artist.imageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
                    } placeholder: {
                Rectangle()
                            .fill(Color.white.opacity(0.2))
                    }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Artist Name
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                
                if let genres = artist.genres, !genres.isEmpty {
                    Text(genres.prefix(2).joined(separator: ", "))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }
}

struct SoundPrintTrackRow: View {
    let track: SpotifyTrack
    let rank: Int
    
    private var albumImageURL: URL? {
        guard let album = track.album,
              let images = album.images,
              let firstImage = images.first else {
            return nil
        }
        // Handle both String and URL types
        if let url = firstImage.url as? URL {
            return url
        } else if let urlString = firstImage.url as? String {
            return URL(string: urlString)
        }
        return nil
    }
    
    private var artistNames: String {
        track.artists.map { $0.name }.joined(separator: ", ")
    }
    
    var body: some View {
                HStack(spacing: 16) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                .frame(width: 30)
            
            // Album Art
            if let url = albumImageURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                            } placeholder: {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Track Info
            VStack(alignment: .leading, spacing: 4) {
                            Text(track.name)
                    .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(artistNames)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
            
            Spacer()
            }
        }
    }

struct ArtistCard: View {
    let artist: SpotifyArtist
    let rank: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank Badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.72, blue: 0.33),
                                Color(red: 0.18, green: 0.80, blue: 0.44)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Text("\(rank)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Artist Image
            AsyncImage(url: artist.imageURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Artist Info
            VStack(alignment: .leading, spacing: 6) {
                Text(artist.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                if let genres = artist.genres, !genres.isEmpty {
                    Text(genres.prefix(3).joined(separator: " • "))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(2)
                }
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct TrackCard: View {
    let track: SpotifyTrack
    let rank: Int
    
    private var albumImageURL: URL? {
        guard let album = track.album,
              let images = album.images,
              let firstImage = images.first else {
            return nil
        }
        // Handle both String and URL types
        if let url = firstImage.url as? URL {
            return url
        } else if let urlString = firstImage.url as? String {
            return URL(string: urlString)
        }
        return nil
    }
    
    private var artistNames: String {
        track.artists.map { $0.name }.joined(separator: ", ")
    }
    
    var body: some View {
                    HStack(spacing: 16) {
            // Rank Badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.72, blue: 0.33),
                                Color(red: 0.18, green: 0.80, blue: 0.44)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Text("\(rank)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Album Art
            if let url = albumImageURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                                } placeholder: {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                                }
                                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            
            // Track Info
            VStack(alignment: .leading, spacing: 6) {
                Text(track.name)
                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                    .lineLimit(2)
                
                Text(artistNames)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct GenreBar: View {
    let genre: String
    let percentage: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(genre.capitalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(Int(percentage * 100))%")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 12)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.72, blue: 0.33),
                                    Color(red: 0.18, green: 0.80, blue: 0.44)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(percentage), height: 12)
                }
            }
            .frame(height: 12)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

// AnimatedGradientBackground is now defined in Views/Shared/AnimatedGradientBackground.swift

