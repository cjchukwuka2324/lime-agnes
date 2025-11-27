import SwiftUI

struct RockListView: View {
    let artistId: String
    
    @StateObject private var viewModel: RockListViewModel
    @State private var showCustomDatePicker = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showShareSheet = false
    @State private var showPostComposer = false
    @State private var composerLeaderboardEntry: LeaderboardEntrySummary?
    @State private var composerPrefilledText: String?
    @State private var showInstagramHandlePrompt = false
    @State private var instagramHandleInput = ""
    @State private var currentInstagramHandle: String?
    @State private var shareImage: UIImage?
    @State private var isGeneratingRankCardImage = false
    
    init(artistId: String) {
        self.artistId = artistId
        self._viewModel = StateObject(wrappedValue: RockListViewModel(artistId: artistId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated gradient background matching SoundPrint
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if case .loading = viewModel.state {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading RockList…")
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else if case .failed(let message) = viewModel.state {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            viewModel.load()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if let rockList = viewModel.rockList {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Artist Header
                            artistHeader(rockList.artist)
                            
                            // Filters
                            filterSection
                            
                            // Current User Rank Card with Share Button
                            if let currentUser = rockList.currentUserEntry {
                                currentUserRankCard(currentUser, artist: rockList.artist)
                            } else {
                                notRankedCard(artist: rockList.artist)
                            }
                            
                            // Comment Input Section (comments display on Feed)
                            commentInputSection
                            
                            // Top 20 RockList
                            top20Section(rockList.top20, currentUserEntry: rockList.currentUserEntry)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("RockList")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                    }
                }
            }
            .onAppear {
                if case .idle = viewModel.state {
                    viewModel.load()
                }
                // Load Instagram handle
                Task {
                    await loadInstagramHandle()
                }
            }
            .sheet(isPresented: $showCustomDatePicker) {
                customDatePickerSheet(isPresented: $showCustomDatePicker)
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = shareImage {
                    ShareSheet(activityItems: [image])
                } else {
                    ShareSheet(activityItems: [viewModel.shareMessage()])
                }
            }
            .sheet(isPresented: $showPostComposer) {
                PostComposerView(
                    leaderboardEntry: composerLeaderboardEntry,
                    prefilledText: composerPrefilledText
                ) {
                    // Post created - navigate to Feed tab
                    NotificationCenter.default.post(name: .navigateToFeed, object: nil)
                    NotificationCenter.default.post(name: .feedDidUpdate, object: nil)
                }
            }
            .sheet(isPresented: $showInstagramHandlePrompt) {
                instagramHandlePromptSheet
            }
            .onChange(of: showInstagramHandlePrompt) { isPresented in
                if isPresented {
                    // Pre-fill Instagram handle if it exists
                    instagramHandleInput = currentInstagramHandle?.replacingOccurrences(of: "@", with: "") ?? ""
                }
            }
        }
    }
    
    // MARK: - Artist Header
    
    @ViewBuilder
    private func artistHeader(_ artist: ArtistSummary) -> some View {
        HStack(spacing: 16) {
            // Try Spotify API image first, then fallback to backend URL
            if let spotifyImageURL = viewModel.artistImageURL {
                AsyncImage(url: spotifyImageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            } else if let imageURL = artist.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(artist.name)
                    .font(.title.bold())
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text(viewModel.selectedRegion.displayName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("•")
                        .foregroundColor(.white.opacity(0.6))
                    
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text(viewModel.selectedTimeFilter.displayName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
        }
        .padding(20)
        .glassMorphism()
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                Text("Filters")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Time Filter
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Time Range")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Picker("Time Range", selection: $viewModel.selectedTimeFilter) {
                    ForEach(TimeFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                    Text("Custom").tag(TimeFilter.custom(start: customStartDate, end: customEndDate))
                }
                .pickerStyle(.segmented)
                .tint(Color(hex: "#1ED760"))
                .onChange(of: viewModel.selectedTimeFilter) { newValue in
                    if case .custom = newValue {
                        showCustomDatePicker = true
                    } else {
                        viewModel.load()
                    }
                }
            }
            
            // Region Filter
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Region")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                
                Menu {
                    ForEach(RegionFilter.allCases) { region in
                        Button {
                            viewModel.selectedRegion = region
                            viewModel.load()
                        } label: {
                            HStack {
                                Text(region.displayName)
                                if viewModel.selectedRegion.id == region.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.selectedRegion.displayName)
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
        }
        .padding(20)
        .glassMorphism()
    }
    
    // MARK: - Current User Rank Card
    
    @ViewBuilder
    private func currentUserRankCard(_ entry: RockListEntry, artist: ArtistSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Artist Header
            HStack(spacing: 12) {
                    // Artist Image - Try Spotify API first, then fallback to backend URL
                    if let spotifyImageURL = viewModel.artistImageURL {
                        AsyncImage(url: spotifyImageURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.2))
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundColor(.white.opacity(0.6))
                                )
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                        )
                    } else if let imageURL = artist.imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.2))
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundColor(.white.opacity(0.6))
                                )
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white.opacity(0.6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Rank")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Text(artist.name)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
                
                Divider()
                    .background(Color.white.opacity(0.3))
                
                // Rank Display
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("#\(entry.rank)")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("of all listeners")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Score")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Text(formatScore(entry.score))
                            .font(.title2.bold())
                            .foregroundColor(.white)
                    }
                }
                
                // User Info
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text(entry.displayName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }
                
                // Social Media Links
                Divider()
                    .background(Color.white.opacity(0.2))
                
                HStack(spacing: 16) {
                    Text("Share your ranking:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    // Instagram Link - Export rank card snapshot to Instagram Stories
                    Button {
                        if let handle = currentInstagramHandle, !handle.isEmpty {
                            // Generate and share rank card to Instagram
                            Task {
                                await generateAndShareRankCardImage(entry: entry, artist: artist, toInstagram: true)
                            }
                        } else {
                            // Prompt for Instagram handle
                            showInstagramHandlePrompt = true
                        }
                    } label: {
                        if isGeneratingRankCardImage {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 36, height: 36)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                    )
                    .disabled(isGeneratingRankCardImage)
                    
                    // Twitter/X Link
                    Link(destination: URL(string: "https://twitter.com/rockoutapp")!) {
                        Image(systemName: "at")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.15))
                            )
                    }
                    
                    // Share Button - Export rank card to social media
                    Button {
                        Task {
                            await generateAndShareRankCardImage(entry: entry, artist: artist, toInstagram: false)
                        }
                    } label: {
                        if isGeneratingRankCardImage {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 36, height: 36)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                        }
                    }
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                    )
                    .disabled(isGeneratingRankCardImage)
                }
            }
            .padding(20)
            .glassMorphism()
    }
    
    // MARK: - Not Ranked Card
    
    @ViewBuilder
    private func notRankedCard(artist: ArtistSummary) -> some View {
        VStack(spacing: 20) {
            // Artist Image - Try Spotify API first, then fallback to backend URL
            if let spotifyImageURL = self.viewModel.artistImageURL {
                AsyncImage(url: spotifyImageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            } else if let imageURL = artist.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            } else {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            
            VStack(spacing: 10) {
                Text("Not Ranked Yet")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Listen to \(artist.name) more to appear on their RockList")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassMorphism()
    }
    
    // MARK: - Comment Input Section
    
    private var commentInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.9))
                Text("Add a Comment")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
            
            if let artistName = viewModel.rockList?.artist.name {
                Text("Your comment will appear in the Feed timeline and reference the \(artistName) RockList leaderboard")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                Text("Your comment will appear in the Feed timeline and reference this artist's RockList leaderboard")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Comment Input
            HStack(spacing: 12) {
                TextField("Add a comment...", text: $viewModel.commentText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.15))
                    )
                    .foregroundColor(.white)
                    .tint(Color(hex: "#1ED760"))
                    .lineLimit(3...6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                
                Button {
                    Task {
                        await viewModel.postComment()
                    }
                } label: {
                    if viewModel.isPostingComment {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color(hex: "#1ED760"))
                            )
                    }
                }
                .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isPostingComment)
            }
        }
        .padding(20)
        .glassMorphism()
    }
    
    // MARK: - Top 20 Section
    
    @ViewBuilder
    private func top20Section(_ entries: [RockListEntry], currentUserEntry: RockListEntry?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(Color(hex: "#FFD700"))
                    .font(.title3)
                Text("Top Listeners")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
            
            ForEach(entries) { entry in
                rockListRow(entry, isCurrentUser: entry.isCurrentUser, artist: viewModel.rockList?.artist)
            }
        }
        .padding(20)
        .glassMorphism()
    }
    
    // MARK: - RockList Row
    
    @ViewBuilder
    private func rockListRow(_ entry: RockListEntry, isCurrentUser: Bool, artist: ArtistSummary?) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Rank
                ZStack {
                    Circle()
                        .fill(
                            isCurrentUser ?
                            LinearGradient(
                                colors: [
                                    Color(hex: "#1ED760").opacity(0.3),
                                    Color(hex: "#1DB954").opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Text("#\(entry.rank)")
                        .font(.headline.weight(.bold))
                        .foregroundColor(isCurrentUser ? Color(hex: "#1ED760") : .white)
                }
                
                // User Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.body.weight(isCurrentUser ? .semibold : .regular))
                        .foregroundColor(.white)
                    
                    if isCurrentUser {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("You")
                                .font(.caption)
                        }
                        .foregroundColor(Color(hex: "#1ED760"))
                    }
                }
                
                Spacer()
                
                // Score
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatScore(entry.score))
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("pts")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Action Buttons
            if let artist = artist {
                HStack(spacing: 12) {
                    Button {
                        let leaderboardEntry = leaderboardEntrySummary(from: entry, artist: artist)
                        composerLeaderboardEntry = leaderboardEntry
                        composerPrefilledText = nil
                        showPostComposer = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left")
                                .font(.caption)
                            Text("Comment")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                    
                    Button {
                        let leaderboardEntry = leaderboardEntrySummary(from: entry, artist: artist)
                        let percentile = calculatePercentile(rank: entry.rank, totalUsers: 100) // Approximate
                        composerLeaderboardEntry = leaderboardEntry
                        composerPrefilledText = "Top \(percentile)% for \(artist.name) this month."
                        showPostComposer = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                            Text("Share")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "#1ED760").opacity(0.3))
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isCurrentUser ?
                    LinearGradient(
                        colors: [
                            Color(hex: "#1ED760").opacity(0.2),
                            Color(hex: "#1DB954").opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isCurrentUser ?
                    LinearGradient(
                        colors: [
                            Color(hex: "#1ED760").opacity(0.4),
                            Color(hex: "#1DB954").opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ) :
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isCurrentUser ? 1.5 : 1
                )
        )
        .shadow(color: Color.black.opacity(isCurrentUser ? 0.3 : 0.2), radius: isCurrentUser ? 8 : 4, x: 0, y: isCurrentUser ? 4 : 2)
    }
    
    // MARK: - Custom Date Picker
    
    @ViewBuilder
    private func customDatePickerSheet(isPresented: Binding<Bool>) -> some View {
        NavigationStack {
            Form {
                Section(header: Text("Start Date")) {
                    DatePicker("Start", selection: $customStartDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section(header: Text("End Date")) {
                    DatePicker("End", selection: $customEndDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Custom Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented.wrappedValue = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        viewModel.selectedTimeFilter = .custom(start: customStartDate, end: customEndDate)
                        viewModel.load()
                        isPresented.wrappedValue = false
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func leaderboardEntrySummary(from entry: RockListEntry, artist: ArtistSummary) -> LeaderboardEntrySummary {
        let artistImageURL: URL? = {
            if let imageURLString = artist.imageURL {
                return URL(string: imageURLString)
            } else {
                return nil
            }
        }()
        
        let totalUsers = 100 // Approximate - in real app, get from API
        let percentile = calculatePercentile(rank: entry.rank, totalUsers: totalUsers)
        let percentileLabel = "Top \(percentile)%"
        
        // Estimate minutes listened from score (assuming 1 point per minute)
        // Ensure score is finite and not NaN before converting
        let safeScore: Double
        if entry.score.isFinite && !entry.score.isNaN {
            safeScore = entry.score
        } else {
            safeScore = 0.0
        }
        let minutesListened = max(0, Int(safeScore.rounded()))
        
        return LeaderboardEntrySummary(
            id: "\(artist.id)-\(entry.userId.uuidString)",
            userId: entry.userId.uuidString,
            userDisplayName: entry.displayName,
            artistId: artist.id,
            artistName: artist.name,
            artistImageURL: artistImageURL,
            rank: entry.rank,
            percentileLabel: percentileLabel,
            minutesListened: minutesListened
        )
    }
    
    private func calculatePercentile(rank: Int, totalUsers: Int) -> Int {
        guard totalUsers > 0, rank > 0 else { return 100 }
        guard rank <= totalUsers else { return 1 }
        let percentile = Double(totalUsers - rank) / Double(totalUsers) * 100.0
        guard percentile.isFinite && !percentile.isNaN else { return 50 }
        return max(1, min(100, Int(percentile.rounded())))
    }
    
    private func formatScore(_ score: Double) -> String {
        guard score.isFinite && !score.isNaN else { return "0" }
        return String(format: "%.0f", score)
    }
    
    // MARK: - Instagram Handle Management
    
    private func loadInstagramHandle() async {
        if let profile = try? await UserProfileService.shared.getCurrentUserProfile() {
            currentInstagramHandle = profile.instagramHandle
        }
    }
    
    private func saveInstagramHandle(_ handle: String) async {
        do {
            try await UserProfileService.shared.updateInstagramHandle(handle)
            await loadInstagramHandle()
            showInstagramHandlePrompt = false
        } catch {
            print("Failed to save Instagram handle: \(error)")
        }
    }
    
    // MARK: - Instagram Handle Prompt Sheet
    
    @ViewBuilder
    private var instagramHandlePromptSheet: some View {
        NavigationStack {
            ZStack {
                // Green gradient background
                LinearGradient(
                    colors: [
                        Color(hex: "#050505"),
                        Color(hex: "#0C7C38"),
                        Color(hex: "#1DB954"),
                        Color(hex: "#1ED760"),
                        Color(hex: "#050505")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                    
                    Text("Add Your Instagram Handle")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text("Link your Instagram to share your RockList rankings to your stories")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instagram Handle")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        HStack {
                            Text("@")
                                .foregroundColor(.white.opacity(0.6))
                            TextField("yourhandle", text: $instagramHandleInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.15))
                        )
                    }
                    .padding(.horizontal)
                    
                    Button {
                        let handle = instagramHandleInput.trimmingCharacters(in: .whitespaces)
                        if !handle.isEmpty {
                            Task {
                                await saveInstagramHandle(handle)
                            }
                        }
                    } label: {
                        Text("Save")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#1ED760"))
                            )
                    }
                    .padding(.horizontal)
                    .disabled(instagramHandleInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationTitle("Instagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showInstagramHandlePrompt = false
                        instagramHandleInput = ""
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    // MARK: - Rank Card Image Generation
    
    @MainActor
    private func generateAndShareRankCardImage(entry: RockListEntry, artist: ArtistSummary, toInstagram: Bool) async {
        guard let rockList = viewModel.rockList else { return }
        
        isGeneratingRankCardImage = true
        defer { isGeneratingRankCardImage = false }
        
        // Create a shareable rank card view
        let rankCardView = RankCardShareableView(
            entry: entry,
            artist: artist,
            displayName: entry.displayName,
            artistImageURL: viewModel.artistImageURL
        )
        
        // Generate image
        shareImage = await ShareExporter.renderImage(rankCardView, width: 1080, scale: 3.0)
        
        if let image = shareImage {
            if toInstagram {
                // Share to Instagram Stories
                shareToInstagramStories(image: image)
            } else {
                // Show share sheet
                showShareSheet = true
            }
        }
    }
    
    private func shareToInstagramStories(image: UIImage) {
        // Instagram Stories URL scheme
        guard let instagramURL = URL(string: "instagram-stories://share") else {
            // Fallback to share sheet
            showShareSheet = true
            return
        }
        
        // Check if Instagram is installed
        if UIApplication.shared.canOpenURL(instagramURL) {
            // Convert image to data
            guard let imageData = image.pngData() else {
                showShareSheet = true
                return
            }
            
            // Share via Instagram Stories
            let pasteboard = UIPasteboard.general
            pasteboard.setData(imageData, forPasteboardType: "public.png")
            
            // Open Instagram Stories
            if let url = URL(string: "instagram-stories://share?source_application=com.rockout.app") {
                UIApplication.shared.open(url, options: [:]) { success in
                    if !success {
                        // Fallback to share sheet
                        DispatchQueue.main.async {
                            self.showShareSheet = true
                        }
                    }
                }
            }
        } else {
            // Instagram not installed, use share sheet
            showShareSheet = true
        }
    }
}

// MARK: - Rank Card Shareable View

struct RankCardShareableView: View {
    let entry: RockListEntry
    let artist: ArtistSummary
    let displayName: String
    let artistImageURL: URL?
    
    var body: some View {
        ZStack {
            AnimatedGradientBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Artist Header
                HStack(spacing: 16) {
                    if let imageURL = artistImageURL {
                        AsyncImage(url: imageURL) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.2))
                                    .overlay(
                                        Image(systemName: "music.note")
                                            .foregroundColor(.white.opacity(0.5))
                                    )
                            }
                        }
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 90, height: 90)
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Rank")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Text(artist.name)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
                
                Divider()
                    .background(Color.white.opacity(0.3))
                
                // Rank Display
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("#\(entry.rank)")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("of all listeners")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Score")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Text(formatScore(entry.score))
                            .font(.title.bold())
                            .foregroundColor(.white)
                    }
                }
                
                // User Info
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))
                    Text(displayName)
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
            .padding(20)
        }
        .frame(width: 1080, height: 1920)
    }
    
    private func formatScore(_ score: Double) -> String {
        guard score.isFinite && !score.isNaN else { return "0" }
        if score >= 1000000 {
            return String(format: "%.1fM", score / 1000000)
        } else if score >= 1000 {
            return String(format: "%.1fK", score / 1000)
        } else {
            return String(format: "%.0f", score)
        }
    }
}

