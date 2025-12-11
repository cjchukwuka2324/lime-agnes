import SwiftUI
import UIKit

struct SoundPrintView: View {
    @EnvironmentObject var authService: SpotifyAuthService
    @StateObject private var spotifyAPI = SpotifyAPI()
    private let spotifyPlaylistService = SpotifyPlaylistService.shared
    private let connectionService = MusicPlatformConnectionService.shared
    private let statsService = ListeningStatsService.shared

    // MARK: - Loaded data (using unified models)
    @State private var profile: UnifiedUserProfile?
    @State private var topArtists: [UnifiedArtist] = []
    @State private var topTracks: [UnifiedTrack] = []
    @State private var genreStats: [GenreStat] = []
    @State private var personality: FanPersonality?
    @State private var currentPlatform: MusicPlatform = .spotify
    
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
    @State private var moreFromYourFaves: MoreFromYourFaves?
    @State private var genreDive: GenreDive?
    @State private var throwbackDiscovery: ThrowbackDiscovery?

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab: Int = 0
    @State private var isAddingToSpotify = false
    @State private var hasMusicPlatformConnection = false
    @State private var selectedStatsTimeRange: StatsTimeRange = .allTime
    @State private var isLoadingStats = false

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
                } else if !hasMusicPlatformConnection {
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
                await checkMusicPlatformConnection()
                await loadData()
            }
        }
    }
    
    // MARK: - Content View
    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ScrollViewOffsetReader()
                        .id("scrollTop")
                    
                    // Hero Header with ID for scrolling
                    heroHeader
                        .id("top")
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
            .detectScroll(collapseThreshold: 50)
            .onChange(of: selectedTab) { _ in
                // Scroll to top when tab changes
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("top", anchor: .top)
                }
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
                
                if let imageURL = profile?.imageURLAsURL {
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
            Text(profile?.displayName ?? "Your SoundPrint")
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
                TabButton(title: "Playlists", icon: "music.note.list", isSelected: selectedTab == 5) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 5
                    }
                }
                TabButton(title: "Analytics", icon: "chart.bar.xaxis", isSelected: selectedTab == 6) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 6
                    }
                }
                TabButton(title: "Share", icon: "square.and.arrow.up", isSelected: selectedTab == 7) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 7
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Overview Tab
    @ViewBuilder
    private var tabContent: some View {
        Group {
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
                statsTab
            case 5:
                discoveryTab
            case 6:
                advancedAnalyticsTab
            case 7:
                socialSharingTab
            default:
                overviewTab
            }
        }
    }
    
    @ViewBuilder
    private var statsTab: some View {
        // Stats Content (always shows all-time data)
        if isLoadingStats {
            loadingPlaceholder
        } else if let stats = listeningStats, let features = audioFeatures {
            ListeningStatsView(stats: stats, audioFeatures: features)
                .id("stats-\(stats.totalListeningTimeMinutes)-\(stats.totalSongsPlayed)") // Force refresh on change
        } else {
            loadingPlaceholder
        }
    }
    
    // MARK: - Time Period Selector
    private var timePeriodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(StatsTimeRange.allCases, id: \.self) { range in
                    Button {
                        guard selectedStatsTimeRange != range else {
                            print("⚠️ [timePeriodSelector] Range \(range.displayName) already selected, skipping")
                            return
                        }
                        print("🔄 [timePeriodSelector] Changing time range from \(selectedStatsTimeRange.displayName) to \(range.displayName)")
                        selectedStatsTimeRange = range
                        Task { @MainActor in
                            await reloadStats(for: range)
                        }
                    } label: {
                        Text(range.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(selectedStatsTimeRange == range ? .black : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(selectedStatsTimeRange == range ? 
                                          Color.white : Color.white.opacity(0.1))
                            )
                    }
                    .disabled(isLoadingStats)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var timeAnalysisTab: some View {
        TimeAnalysisView(yearInMusic: yearInMusic, monthlyEvolution: monthlyEvolution)
    }
    
    private var discoveryTab: some View {
        Group {
            DiscoveryView(
                realYouMix: realYouMix,
                soundprintForecast: soundprintForecast,
                moreFromYourFaves: moreFromYourFaves,
                genreDive: genreDive,
                throwbackDiscovery: throwbackDiscovery,
                moodPlaylists: moodPlaylists,
                onOpenInSpotify: handleOpenInSpotify
            )
        }
    }
    
    private var socialSharingTab: some View {
        SocialSharingView(
            profile: profile,
            topArtists: topArtists,
            topTracks: topTracks,
            personality: personality,
            compatibility: tasteCompatibility.isEmpty ? nil : tasteCompatibility,
            genreStats: genreStats,
            listeningStats: listeningStats,
            audioFeatures: audioFeatures
        )
    }
    
    private var moodContextTab: some View {
        MoodContextView(
            moodPlaylists: moodPlaylists,
            timePatterns: timePatterns,
            seasonalTrends: seasonalTrends
        )
    }
    
    @ViewBuilder
    private var advancedAnalyticsTab: some View {
        if let diversity = diversity, let features = audioFeatures {
            AdvancedAnalyticsView(diversity: diversity, audioFeatures: features)
        } else {
            loadingPlaceholder
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
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    selectedTab = 2 // Navigate to Tracks tab
                }
            }
        }
    }
    
    private var topTracksPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Tracks")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 2 // Navigate to Tracks tab
                    }
                } label: {
                    Text("See All")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                }
            }
            
            ForEach(Array(topTracks.prefix(3).enumerated()), id: \.element.id) { index, track in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 2 // Navigate to Tracks tab
                    }
                } label: {
                    SoundPrintTrackRow(track: track, rank: index + 1)
                }
                .buttonStyle(PlainButtonStyle())
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
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = 1 // Navigate to Artists tab
                    }
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
                .foregroundColor(.white.opacity(0.8))
            
            Text("Connect Your Music Platform")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text("Connect your music platform to view your personalized SoundPrint")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Check Music Platform Connection
    private func checkMusicPlatformConnection() async {
        do {
            let connection = try await connectionService.getConnection()
            hasMusicPlatformConnection = connection != nil
        } catch {
            print("Failed to check music platform connection: \(error)")
            hasMusicPlatformConnection = false
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
        VStack(spacing: 24) {
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
            
            // Add button to navigate to Profile if error mentions Profile
            if message.contains("Profile") || message.contains("Settings") {
                Button {
                    // Navigate to Profile tab
                    if let url = URL(string: "rockout://profile") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Go to Profile")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.12, green: 0.72, blue: 0.33))
                        )
                }
                .padding(.top, 8)
            }
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
        // Only load data if user has a music platform connection
        guard hasMusicPlatformConnection else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        // Check which platform is connected
        let connection: MusicPlatformConnectionService.MusicPlatformConnection?
        do {
            connection = try await connectionService.getConnection()
            
            guard let conn = connection else {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "No music platform connection found. Please connect Spotify in Profile."
                }
                return
            }
            
            // SoundPrint is currently Spotify-only
            guard conn.platform == "spotify" else {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "SoundPrint is currently only available for Spotify. Please connect your Spotify account in Profile."
                }
                return
            }
            
            await MainActor.run {
                currentPlatform = .spotify
            }
            
            // Check if authorized, and if not, try to refresh the token
            if !authService.isAuthorized() {
                // First, reload connection from database
                await authService.loadConnection()
                
                // If still not authorized, try to refresh the access token
                if !authService.isAuthorized() {
                    do {
                        // This will refresh the token if we have a refresh token
                        _ = try await authService.refreshAccessTokenIfNeeded()
                        
                        // Check authorization again after refresh
                        guard authService.isAuthorized() else {
                            await MainActor.run {
                                isLoading = false
                                errorMessage = "Your Spotify session has expired. The connection is permanent, but you may need to re-authorize. Please check your connection in Profile."
                            }
                            return
                        }
                    } catch {
                        await MainActor.run {
                            isLoading = false
                            errorMessage = "Failed to refresh Spotify connection: \(error.localizedDescription). Please check your connection in Profile."
                        }
                        return
                    }
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to check music platform connection: \(error.localizedDescription)"
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            // Load Spotify data
            let p = try await spotifyAPI.getUserProfile()
            let artistsResponse = try await spotifyAPI.getTopArtists(limit: 20)
            let tracksResponse = try await spotifyAPI.getTopTracks(limit: 20)
            
            let unifiedProfile = p.toUnified()
            let unifiedArtists = artistsResponse.items.map { $0.toUnified() }
            let unifiedTracks = tracksResponse.items.map { $0.toUnified() }
            
            let genres = computeGenres(from: unifiedArtists)
            let pers = FanPersonalityEngine.compute(artists: unifiedArtists, tracks: unifiedTracks)
            
            // Load extended features (with error handling - don't fail if these don't work)
            // Always load all-time stats
            async let statsTask = loadListeningStats(timeRange: .allTime)
            async let featuresTask = loadAudioFeatures(tracks: unifiedTracks)
            async let timeTask = loadTimeAnalysis()
            async let discoveryTask = loadDiscovery()
            async let analyticsTask = loadAnalytics(artists: unifiedArtists, tracks: unifiedTracks)
            
            // Generate time patterns for Mood tab
            await MainActor.run {
                self.timePatterns = generateTimePatterns()
            }

            await MainActor.run {
                self.profile = unifiedProfile
                self.topArtists = unifiedArtists
                self.topTracks = unifiedTracks
                self.genreStats = genres
                self.personality = pers
            }
            
            // Load RockList data for all artists (non-blocking)
            Task {
                await ensureRockListDataForArtists(unifiedArtists)
            }
            
            // Load extended data (non-blocking)
            _ = try? await statsTask
            _ = try? await featuresTask
            _ = try? await timeTask
            _ = try? await discoveryTask
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
    
    private func ensureRockListDataForArtists(_ artists: [UnifiedArtist]) async {
        // RockList data ingestion works for both platforms via cross-platform matching
        // Only proceed if we have a music platform connection
        guard hasMusicPlatformConnection else {
            print("ℹ️ SoundPrint: No music platform connection, skipping RockList data ingestion")
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
    private func loadListeningStats(timeRange: StatsTimeRange = .allTime) async throws {
        print("📊 [loadListeningStats] Starting load for time range: \(timeRange.displayName) (\(timeRange.daysBack.map { "\($0)" } ?? "all time") days)")
        
        // Fetch filtered play history for the selected time range
        let playHistory = try await statsService.fetchPlayHistory(limit: 500, daysBack: timeRange.daysBack)
        print("📊 [loadListeningStats] Fetched \(playHistory.count) play history items for selected range")
        
        // For discovery metrics, we need all history to compare against
        // Only fetch all history if we're using a filtered range (not "All Time")
        let allHistoryForComparison: [ListeningStatsService.PlayHistoryItem]?
        if timeRange != .allTime {
            allHistoryForComparison = try? await statsService.fetchPlayHistory(limit: 500, daysBack: nil)
            print("📊 [loadListeningStats] Fetched \(allHistoryForComparison?.count ?? 0) total items for discovery comparison")
        } else {
            allHistoryForComparison = nil
        }
        
        // Calculate stats from filtered play history with context
        let stats = statsService.calculateStats(
            history: playHistory,
            daysBack: timeRange.daysBack,
            allHistory: allHistoryForComparison
        )
        
        print("✅ [loadListeningStats] Stats calculated successfully")
        
        // Calculate audio features from top tracks within the selected time range
        // Filter topTracks by matching track IDs in the filtered play history
        let filteredTrackIds = Set(playHistory.map { $0.trackId })
        let filteredTopTracks = topTracks.filter { filteredTrackIds.contains($0.id) }
        let topTrackIds = Array(filteredTopTracks.prefix(50).map { $0.id })
        
        print("📊 [loadListeningStats] Using \(topTrackIds.count) tracks for audio features (filtered from \(topTracks.count) total)")
        
        let features: AverageAudioFeatures
        
        if !topTrackIds.isEmpty && currentPlatform == .spotify {
            do {
                features = try await statsService.calculateAudioFeatures(
                    trackIds: topTrackIds,
                    platform: currentPlatform
                )
                print("✅ Calculated audio features from \(topTrackIds.count) tracks")
            } catch {
                print("⚠️ Failed to fetch audio features: \(error.localizedDescription)")
                // Fallback to default values
                features = AverageAudioFeatures(
                    danceability: 0.5, energy: 0.5, valence: 0.5, tempo: 120,
                    acousticness: 0.5, instrumentalness: 0.5, liveness: 0.5, speechiness: 0.5
                )
            }
        } else {
            // Use default values if no tracks
            features = AverageAudioFeatures(
                danceability: 0.5, energy: 0.5, valence: 0.5, tempo: 120,
                acousticness: 0.5, instrumentalness: 0.5, liveness: 0.5, speechiness: 0.5
            )
        }
        
        await MainActor.run {
            print("📊 [loadListeningStats] Updating UI state with new stats")
            self.listeningStats = stats
            self.audioFeatures = features
            print("📊 [loadListeningStats] State updated - listeningStats: \(stats != nil ? "set" : "nil"), audioFeatures: \(features != nil ? "set" : "nil")")
        }
    }
    
    // MARK: - Reload Stats for Time Range
    private func reloadStats(for timeRange: StatsTimeRange) async {
        print("🔄 [reloadStats] Reloading stats for: \(timeRange.displayName)")
        
        await MainActor.run {
            self.isLoadingStats = true
            print("🔄 [reloadStats] Set isLoadingStats = true")
        }
        
        do {
            try await loadListeningStats(timeRange: timeRange)
            print("✅ [reloadStats] Successfully reloaded stats")
        } catch {
            print("⚠️ [reloadStats] Failed to reload stats: \(error.localizedDescription)")
        }
        
        await MainActor.run {
            self.isLoadingStats = false
            print("🔄 [reloadStats] Set isLoadingStats = false")
        }
    }
    
    private func loadAudioFeatures(tracks: [UnifiedTrack]) async throws {
        // Audio features are now loaded in loadListeningStats() along with stats
        // This method is kept for compatibility but will use the same logic
        guard !tracks.isEmpty && currentPlatform == .spotify else {
            let features = AverageAudioFeatures(
                danceability: 0.5, energy: 0.5, valence: 0.5, tempo: 120,
                acousticness: 0.5, instrumentalness: 0.5, liveness: 0.5, speechiness: 0.5
            )
            await MainActor.run {
                self.audioFeatures = features
            }
            return
        }
        
        let trackIds = Array(tracks.prefix(50).map { $0.id })
        let features = try await statsService.calculateAudioFeatures(
            trackIds: trackIds,
            platform: currentPlatform
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
        // Load platform-specific playlists
        // Load Spotify's native playlists
            do {
                // Find Discover Weekly
                if let discoverWeeklyPlaylist = try await spotifyAPI.findDiscoverWeekly() {
                    let tracks = try await spotifyAPI.getAllPlaylistTracks(playlistId: discoverWeeklyPlaylist.id)
                    let unifiedTracks = tracks.map { $0.toUnified() }
                    await MainActor.run {
                        self.discoverWeekly = DiscoverWeekly(tracks: unifiedTracks, updatedAt: Date(), playlistId: discoverWeeklyPlaylist.id)
                    }
                } else {
                    await MainActor.run {
                        self.discoverWeekly = DiscoverWeekly(tracks: [], updatedAt: Date(), playlistId: nil)
                    }
                }
                
                // Find Release Radar
                if let releaseRadarPlaylist = try await spotifyAPI.findReleaseRadar() {
                    let tracks = try await spotifyAPI.getAllPlaylistTracks(playlistId: releaseRadarPlaylist.id)
                    let unifiedTracks = tracks.map { $0.toUnified() }
                    await MainActor.run {
                        self.releaseRadar = ReleaseRadar(tracks: unifiedTracks, updatedAt: Date(), playlistId: releaseRadarPlaylist.id)
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
        // Note: DiscoveryEngine uses SpotifyAPI - SoundPrint is Spotify-only
        
        // Fetch play history for playlist generation
        let playHistory: [ListeningStatsService.PlayHistoryItem]?
        do {
            playHistory = try await statsService.fetchPlayHistory(limit: 500, daysBack: nil)
            print("📊 Loaded \(playHistory?.count ?? 0) play history items for playlist generation")
        } catch {
            print("⚠️ Failed to fetch play history for playlists: \(error.localizedDescription)")
            playHistory = nil
        }
        
        let discoveryEngine = DiscoveryEngine(api: spotifyAPI)
        
        // Convert unified models to Spotify models for DiscoveryEngine
        // (DiscoveryEngine uses Spotify's recommendation API which is Spotify-specific)
        let spotifyArtists = topArtists.filter { $0.platform == .spotify }.compactMap { unifiedArtist -> SpotifyArtist? in
            // Find original SpotifyArtist from topArtists if available
            // For now, create a minimal SpotifyArtist from UnifiedArtist
            SpotifyArtist(
                id: unifiedArtist.id,
                name: unifiedArtist.name,
                images: unifiedArtist.imageURL.map { urlString in
                    [SpotifyImage(url: urlString, width: nil, height: nil)]
                },
                genres: unifiedArtist.genres.isEmpty ? nil : unifiedArtist.genres,
                popularity: unifiedArtist.popularity
            )
        }
        
        let spotifyTracks = topTracks.filter { $0.platform == .spotify }.compactMap { unifiedTrack -> SpotifyTrack? in
            // Create minimal SpotifyTrack from UnifiedTrack
            SpotifyTrack(
                id: unifiedTrack.id,
                name: unifiedTrack.name,
                album: unifiedTrack.album.map { album in
                    SpotifyAlbum(
                        id: album.id,
                        name: album.name,
                        images: album.imageURL.map { urlString in
                            [SpotifyImage(url: urlString, width: nil, height: nil)]
                        },
                        release_date: nil,
                        release_date_precision: nil,
                        album_type: nil
                    )
                },
                artists: unifiedTrack.artists.map { artist in
                    SpotifyArtist(
                        id: artist.id,
                        name: artist.name,
                        images: artist.imageURL.map { urlString in
                            [SpotifyImage(url: urlString, width: nil, height: nil)]
                        },
                        genres: artist.genres.isEmpty ? nil : artist.genres,
                        popularity: artist.popularity
                    )
                },
                popularity: nil,
                duration_ms: unifiedTrack.durationMs,
                preview_url: unifiedTrack.previewURL
            )
        }
        
        // Build Real You Mix with play history
        do {
            print("🔄 [loadDiscovery] Building Real You Mix...")
            print("   - Genre stats: \(genreStats.count)")
            print("   - Top artists: \(spotifyArtists.count)")
            print("   - Top tracks: \(spotifyTracks.count)")
            print("   - Play history items: \(playHistory?.count ?? 0)")
            
            let realYou = try await discoveryEngine.buildRealYouMix(
                genres: genreStats,
                topArtists: spotifyArtists,
                topTracks: spotifyTracks,
                playHistory: playHistory
            )
            await MainActor.run {
                self.realYouMix = realYou
            }
            print("✅ [loadDiscovery] Real You Mix built: \(realYou.tracks.count) tracks")
        } catch {
            print("❌ [loadDiscovery] Failed to build Real You Mix: \(error.localizedDescription)")
            print("   Error details: \(error)")
            // Create fallback Real You Mix with top tracks
            if !spotifyTracks.isEmpty && !genreStats.isEmpty {
                let fallbackTracks = Array(spotifyTracks.prefix(30))
                let coreGenres = Array(genreStats.sorted { $0.percent > $1.percent }.prefix(3))
                let fallbackRealYou = RealYouMix(
                    title: "The Real You",
                    subtitle: "Your core sound right now",
                    description: "Based on your top tracks",
                    genres: coreGenres,
                    tracks: fallbackTracks.map { $0.toUnified() }
                )
                await MainActor.run {
                    self.realYouMix = fallbackRealYou
                }
                print("✅ Created fallback Real You Mix with \(fallbackTracks.count) tracks")
            } else {
                await MainActor.run {
                    self.realYouMix = nil
                }
            }
        }
        
        // Build Soundprint Forecast with play history
        do {
            let forecast = try await discoveryEngine.buildForecast(
                genres: genreStats,
                topArtists: spotifyArtists,
                topTracks: spotifyTracks,
                playHistory: playHistory
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
        
        // Build More from your faves
        do {
            let moreFaves = try await discoveryEngine.buildMoreFromYourFaves(
                playHistory: playHistory ?? [],
                topArtists: spotifyArtists,
                audioFeatures: audioFeatures
            )
            await MainActor.run {
                self.moreFromYourFaves = moreFaves
            }
            print("✅ More from your faves built: \(moreFaves.tracks.count) tracks")
        } catch {
            print("⚠️ Failed to build More from your faves: \(error.localizedDescription)")
            // Create fallback with top tracks from top artists
            if !spotifyArtists.isEmpty && !spotifyTracks.isEmpty {
                let topArtistIds = Set(spotifyArtists.prefix(5).map { $0.id })
                let artistTracks = spotifyTracks.filter { track in
                    track.artists.contains { topArtistIds.contains($0.id) }
                }
                let fallbackTracks = Array(artistTracks.prefix(24))
                if !fallbackTracks.isEmpty {
                    let fallbackMoreFaves = MoreFromYourFaves(tracks: fallbackTracks.map { $0.toUnified() })
                    await MainActor.run {
                        self.moreFromYourFaves = fallbackMoreFaves
                    }
                    print("✅ Created fallback More from your faves with \(fallbackTracks.count) tracks")
                } else {
                    await MainActor.run {
                        self.moreFromYourFaves = nil
                    }
                }
            } else {
                await MainActor.run {
                    self.moreFromYourFaves = nil
                }
            }
        }
        
        // Build Genre Dive
        do {
            print("🔄 [loadDiscovery] Building Genre Dive...")
            let dive = try await discoveryEngine.buildGenreDive(
                playHistory: playHistory ?? [],
                genreStats: genreStats,
                topArtists: spotifyArtists
            )
            await MainActor.run {
                self.genreDive = dive
            }
            print("✅ [loadDiscovery] Genre Dive built: \(dive.tracks.count) tracks for genre '\(dive.genre)'")
        } catch {
            print("❌ [loadDiscovery] Failed to build Genre Dive: \(error.localizedDescription)")
            print("   Error details: \(error)")
            // Create fallback Genre Dive with top genre and recommendations
            if !genreStats.isEmpty && !spotifyArtists.isEmpty {
                let topGenre = genreStats.sorted { $0.percent > $1.percent }.first!
                let genreArtists = spotifyArtists.filter { artist in
                    artist.genres?.contains { $0.lowercased() == topGenre.genre.lowercased() } ?? false
                }
                let genreTracks = spotifyTracks.filter { track in
                    track.artists.contains { artist in
                        genreArtists.contains { $0.id == artist.id }
                    }
                }
                let fallbackTracks = Array(genreTracks.prefix(20))
                if !fallbackTracks.isEmpty {
                    let fallbackDive = GenreDive(
                        genre: topGenre.genre,
                        tracks: fallbackTracks.map { $0.toUnified() },
                        description: "A dive into \(topGenre.genre)"
                    )
                    await MainActor.run {
                        self.genreDive = fallbackDive
                    }
                    print("✅ Created fallback Genre Dive with \(fallbackTracks.count) tracks")
                } else {
                    await MainActor.run {
                        self.genreDive = nil
                    }
                }
            } else {
                await MainActor.run {
                    self.genreDive = nil
                }
            }
        }
        
        // Build Throwback Discovery
        do {
            print("🔄 [loadDiscovery] Building Throwback Discovery...")
            let throwback = try await discoveryEngine.buildThrowbackDiscovery(
                playHistory: playHistory ?? [],
                topArtists: spotifyArtists
            )
            await MainActor.run {
                self.throwbackDiscovery = throwback
            }
            print("✅ [loadDiscovery] Throwback Discovery built: \(throwback.tracks.count) tracks")
        } catch {
            print("❌ [loadDiscovery] Failed to build Throwback Discovery: \(error.localizedDescription)")
            print("   Error details: \(error)")
            // Create fallback Throwback Discovery with top tracks
            if !spotifyTracks.isEmpty {
                // Use middle section of top tracks as "throwback"
                let midPoint = max(10, min(spotifyTracks.count / 2, spotifyTracks.count - 15))
                let fallbackTracks = Array(spotifyTracks[midPoint..<min(midPoint + 20, spotifyTracks.count)])
                if !fallbackTracks.isEmpty {
                    let fallbackThrowback = ThrowbackDiscovery(
                        tracks: fallbackTracks.map { $0.toUnified() },
                        description: "Tracks from your collection"
                    )
                    await MainActor.run {
                        self.throwbackDiscovery = fallbackThrowback
                    }
                    print("✅ Created fallback Throwback Discovery with \(fallbackTracks.count) tracks")
                } else {
                    await MainActor.run {
                        self.throwbackDiscovery = nil
                    }
                }
            } else {
                await MainActor.run {
                    self.throwbackDiscovery = nil
                }
            }
        }
        
        // Build Mood Playlists (replaces old loadMoodData)
        do {
            print("🔄 [loadDiscovery] Building Mood Playlists...")
            let moods = try await discoveryEngine.buildMoodPlaylists(
                playHistory: playHistory ?? [],
                topTracks: spotifyTracks
            )
            await MainActor.run {
                self.moodPlaylists = moods
            }
            print("✅ [loadDiscovery] Mood playlists built: \(moods.count) playlists")
            for mood in moods {
                print("   - \(mood.mood): \(mood.tracks.count) tracks")
            }
        } catch {
            print("❌ [loadDiscovery] Failed to build mood playlists: \(error.localizedDescription)")
            print("   Error details: \(error)")
            await MainActor.run {
                self.moodPlaylists = []
            }
        }
        
        // Debug: Print final state of all playlists
        await MainActor.run {
            print("📊 [loadDiscovery] Final playlist state:")
            print("   - Real You Mix: \(realYouMix != nil ? "\(realYouMix!.tracks.count) tracks" : "nil")")
            print("   - Soundprint Forecast: \(soundprintForecast != nil ? "\(soundprintForecast!.suggestedTracks.count) tracks" : "nil")")
            print("   - More from your faves: \(moreFromYourFaves != nil ? "\(moreFromYourFaves!.tracks.count) tracks" : "nil")")
            print("   - Genre Dive: \(genreDive != nil ? "\(genreDive!.tracks.count) tracks" : "nil")")
            print("   - Throwback Discovery: \(throwbackDiscovery != nil ? "\(throwbackDiscovery!.tracks.count) tracks" : "nil")")
            print("   - Mood Playlists: \(moodPlaylists.count) playlists")
        }
    }
    
    private func loadAnalytics(artists: [UnifiedArtist], tracks: [UnifiedTrack]) async throws {
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
    private func generateMoodPlaylists(from tracks: [UnifiedTrack]) -> [MoodPlaylist] {
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
    
    private func calculateDiversityScore(artists: [UnifiedArtist], tracks: [UnifiedTrack]) -> Double {
        // Simple diversity calculation
        let uniqueGenres = Set(genreStats.map { $0.genre })
        let genreScore = min(Double(uniqueGenres.count) / 20.0 * 50, 50)
        let artistScore = min(Double(artists.count) / 50.0 * 50, 50)
        return genreScore + artistScore
    }
    
    private func handleOpenInSpotify(playlistName: String, tracks: [UnifiedTrack]) {
        Task {
            await MainActor.run {
                isAddingToSpotify = true
            }
            
            do {
                if currentPlatform == .spotify {
                    // Create the playlist first
                    let trackUris = tracks.filter { $0.platform == .spotify }.map { track in
                        "spotify:track:\(track.id)"
                    }
                    
                    let playlistId = try await spotifyPlaylistService.createPlaylistAndAddTracks(
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
                }
            } catch {
                await MainActor.run {
                    isAddingToSpotify = false
                    errorMessage = "Failed to create playlist: \(error.localizedDescription)"
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

    func computeGenres(from artists: [UnifiedArtist]) -> [GenreStat] {
        var counts: [String: Int] = [:]
        for artist in artists {
            for g in artist.genres {
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
    let artist: UnifiedArtist
    let rank: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                .frame(width: 30)
            
            // Artist Image
            AsyncImage(url: artist.imageURL.flatMap { URL(string: $0) }) { image in
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
                
                if !artist.genres.isEmpty {
                    Text(artist.genres.prefix(2).joined(separator: ", "))
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
    let track: UnifiedTrack
    let rank: Int
    
    private var albumImageURL: URL? {
        guard let album = track.album,
              let imageURL = album.imageURL else {
            return nil
        }
        return URL(string: imageURL)
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
    let artist: UnifiedArtist
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
            AsyncImage(url: artist.imageURL.flatMap { URL(string: $0) }) { image in
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
                
                if !artist.genres.isEmpty {
                    Text(artist.genres.prefix(3).joined(separator: " • "))
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
    let track: UnifiedTrack
    let rank: Int
    
    private var albumImageURL: URL? {
        guard let album = track.album,
              let imageURL = album.imageURL else {
            return nil
        }
        return URL(string: imageURL)
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

