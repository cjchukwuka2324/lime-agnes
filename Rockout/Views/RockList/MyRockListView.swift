import SwiftUI

struct MyRockListView: View {
    @StateObject private var viewModel = MyRockListViewModel()
    @State private var showCustomDatePicker = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Glass morphism background gradient
                LinearGradient(
                    colors: [
                        Color(hex: "#0A0A0A"),
                        Color(hex: "#1A1A2E"),
                        Color(hex: "#16213E")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading your RockList…")
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
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
                } else if viewModel.myRockListRanks.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.6))
                        Text("No Rankings Yet")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Start listening to your favorite artists to see your RockList rankings, or sync your Spotify data to populate rankings now.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        // Manual sync button
                        Button {
                            Task {
                                await viewModel.triggerIngestionIfNeeded()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Sync Spotify Data")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: "#1ED760"))
                            )
                        }
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Filters
                            filterSection
                            
                            // Top 10 Section
                            if !viewModel.topRanks.isEmpty {
                                topRanksSection
                            }
                            
                            // Other Ranks Section
                            if !viewModel.otherRanks.isEmpty {
                                otherRanksSection
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("My RockList")
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
                // Always load data when view appears
                if !viewModel.isLoading {
                    viewModel.load()
                    
                    // If no data found, trigger ingestion in background
                    Task {
                        // Wait a bit for initial load to complete
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                        
                        // If still no data after load, trigger ingestion
                        if viewModel.myRockListRanks.isEmpty {
                            await viewModel.triggerIngestionIfNeeded()
                        }
                    }
                }
            }
            .sheet(isPresented: $showCustomDatePicker) {
                customDatePickerSheet
            }
        }
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
    
    // MARK: - Top Ranks Section
    
    private var topRanksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(Color(hex: "#FFD700"))
                    .font(.title3)
                Text("Top 10 Rankings")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
            
            ForEach(viewModel.topRanks) { rank in
                artistRankRow(rank)
            }
        }
    }
    
    // MARK: - Other Ranks Section
    
    private var otherRanksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.title3)
                Text("Other Rankings")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
            
            ForEach(viewModel.otherRanks) { rank in
                artistRankRow(rank)
            }
        }
    }
    
    // MARK: - Artist Rank Row
    
    @ViewBuilder
    private func artistRankRow(_ rank: MyRockListRank) -> some View {
        NavigationLink {
            RockListView(artistId: rank.artistId)
        } label: {
            HStack(spacing: 16) {
                // Artist Image - Try Spotify API first, then fallback to backend URL
                if let spotifyImageURL = viewModel.artistImages[rank.artistId] {
                    AsyncImage(url: spotifyImageURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
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
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                } else if let imageURL = rank.artistImageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
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
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                } else {
                    RoundedRectangle(cornerRadius: 12)
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
                        .frame(width: 70, height: 70)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(.white.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                
                // Artist Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(rank.artistName)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if let myRank = rank.myRank {
                        HStack(spacing: 6) {
                            Text("You are #\(myRank)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Color(hex: "#1ED760"))
                            
                            if let score = rank.myScore {
                                Text("• \(String(format: "%.0f", score)) pts")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    } else {
                        Text("Not ranked yet")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(16)
            .glassMorphism()
        }
        .buttonStyle(.plain)
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

// MARK: - Glass Morphism Modifier

extension View {
    func glassMorphism() -> some View {
        self
            .background(
                ZStack {
                    // Base blur effect
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    
                    // Subtle gradient overlay
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
            .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}

