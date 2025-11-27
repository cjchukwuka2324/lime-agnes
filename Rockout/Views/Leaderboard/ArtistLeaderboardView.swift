import SwiftUI

struct ArtistLeaderboardView: View {
    let artistId: String
    
    @StateObject private var viewModel: ArtistLeaderboardViewModel
    @State private var showCustomDatePicker = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    
    init(artistId: String) {
        self.artistId = artistId
        self._viewModel = StateObject(wrappedValue: ArtistLeaderboardViewModel(artistId: artistId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if case .loading = viewModel.state {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading leaderboard…")
                            .foregroundColor(.secondary)
                    }
                } else if case .failed(let message) = viewModel.state {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            viewModel.load()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if let leaderboard = viewModel.leaderboard {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Artist Header
                            artistHeader(leaderboard.artist)
                            
                            // Filters
                            filterSection
                            
                            // Current User Rank Card
                            if let currentUser = leaderboard.currentUserEntry {
                                currentUserRankCard(currentUser)
                            } else {
                                notRankedCard
                            }
                            
                            // Top 20 Leaderboard
                            top20Section(leaderboard.top20, currentUserEntry: leaderboard.currentUserEntry)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Leaderboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
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
        }
    }
    
    // MARK: - Artist Header
    
    @ViewBuilder
    private func artistHeader(_ artist: ArtistSummary) -> some View {
        HStack(spacing: 16) {
            if let imageURL = artist.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 80)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.title2.bold())
                
                Text("\(viewModel.selectedRegion.displayName) • \(viewModel.selectedTimeFilter.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.headline)
            
            // Time Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("Time Range")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Time Range", selection: $viewModel.selectedTimeFilter) {
                    ForEach(TimeFilter.allCases) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                    Text("Custom").tag(TimeFilter.custom(start: customStartDate, end: customEndDate))
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedTimeFilter) { newValue in
                    if case .custom = newValue {
                        showCustomDatePicker = true
                    } else {
                        viewModel.load()
                    }
                }
            }
            
            // Region Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("Region")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("Region", selection: $viewModel.selectedRegion) {
                    ForEach(RegionFilter.allCases) { region in
                        Text(region.displayName).tag(region)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedRegion) { _ in
                    viewModel.load()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Current User Rank Card
    
    @ViewBuilder
    private func currentUserRankCard(_ entry: ArtistLeaderboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Your Rank")
                    .font(.headline)
                
                Spacer()
            }
            
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("#\(entry.rank)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.blue)
                
                Text("of all listeners")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Score")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f", entry.score))
                        .font(.headline)
                }
            }
            
            Text(entry.displayName)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
    
    // MARK: - Not Ranked Card
    
    private var notRankedCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("You are not ranked yet")
                .font(.headline)
            
            Text("Listen more to appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Top 20 Section
    
    @ViewBuilder
    private func top20Section(_ entries: [ArtistLeaderboardEntry], currentUserEntry: ArtistLeaderboardEntry?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Listeners")
                .font(.title2.bold())
            
            ForEach(entries) { entry in
                leaderboardRow(entry, isCurrentUser: entry.isCurrentUser)
            }
        }
    }
    
    // MARK: - Leaderboard Row
    
    @ViewBuilder
    private func leaderboardRow(_ entry: ArtistLeaderboardEntry, isCurrentUser: Bool) -> some View {
        HStack(spacing: 12) {
            // Rank
            Text("#\(entry.rank)")
                .font(.headline)
                .foregroundColor(isCurrentUser ? .blue : .primary)
                .frame(width: 40, alignment: .leading)
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.body)
                    .fontWeight(isCurrentUser ? .semibold : .regular)
                    .foregroundColor(isCurrentUser ? .blue : .primary)
                
                if isCurrentUser {
                    Text("You")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            // Score
            Text(String(format: "%.0f", entry.score))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(isCurrentUser ? Color.blue.opacity(0.1) : Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrentUser ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(8)
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

