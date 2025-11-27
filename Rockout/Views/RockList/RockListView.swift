import SwiftUI

struct RockListView: View {
    let artistId: String
    
    @StateObject private var viewModel: RockListViewModel
    @State private var showCustomDatePicker = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var showShareSheet = false
    
    init(artistId: String) {
        self.artistId = artistId
        self._viewModel = StateObject(wrappedValue: RockListViewModel(artistId: artistId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // STRONG MULTI-PASS SPOTIFY GRADIENT BACKGROUND (matching SoundPrint)
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
            }
            .sheet(isPresented: $showCustomDatePicker) {
                customDatePickerSheet
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: [viewModel.shareMessage()])
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
        ZStack {
            // Gradient background matching SoundPrint style
            LinearGradient(
                colors: [
                    Color(hex: "#1ED760"),
                    Color(hex: "#1DB954"),
                    Color(hex: "#109C4B")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .cornerRadius(20)
            
            // Content
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
                    
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                            .font(.title3)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
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
                        Text(String(format: "%.0f", entry.score))
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
            }
            .padding(20)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
    }
    
    // MARK: - Not Ranked Card
    
    @ViewBuilder
    private func notRankedCard(artist: ArtistSummary) -> some View {
        VStack(spacing: 20) {
            // Artist Image - Try Spotify API first, then fallback to backend URL
            if let spotifyImageURL = viewModel.artistImageURL {
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
            
            Text("Your comment will appear in the Feed timeline")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
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
                rockListRow(entry, isCurrentUser: entry.isCurrentUser)
            }
        }
    }
    
    // MARK: - RockList Row
    
    @ViewBuilder
    private func rockListRow(_ entry: RockListEntry, isCurrentUser: Bool) -> some View {
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
                Text(String(format: "%.0f", entry.score))
                    .font(.headline)
                    .foregroundColor(.white)
                Text("pts")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
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
    
    private var customDatePickerSheet: some View {
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
                        showCustomDatePicker = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        viewModel.selectedTimeFilter = .custom(start: customStartDate, end: customEndDate)
                        viewModel.load()
                        showCustomDatePicker = false
                    }
                }
            }
        }
    }
}

