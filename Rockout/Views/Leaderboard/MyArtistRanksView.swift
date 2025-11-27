import SwiftUI

struct MyArtistRanksView: View {
    @StateObject private var viewModel = MyArtistRanksViewModel()
    @State private var showCustomDatePicker = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading your ranks…")
                            .foregroundColor(.secondary)
                    }
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                        Text(error)
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
                } else if viewModel.myArtistRanks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Rankings Yet")
                            .font(.headline)
                        Text("Start listening to your favorite artists to see your rankings")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
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
            .navigationTitle("My Leaderboards")
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
                if viewModel.myArtistRanks.isEmpty && !viewModel.isLoading {
                    viewModel.load()
                }
            }
            .sheet(isPresented: $showCustomDatePicker) {
                customDatePickerSheet
            }
        }
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
    
    // MARK: - Top Ranks Section
    
    private var topRanksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top 10 Rankings")
                .font(.title2.bold())
            
            ForEach(viewModel.topRanks) { rank in
                artistRankRow(rank)
            }
        }
    }
    
    // MARK: - Other Ranks Section
    
    private var otherRanksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other Rankings")
                .font(.title2.bold())
            
            ForEach(viewModel.otherRanks) { rank in
                artistRankRow(rank)
            }
        }
    }
    
    // MARK: - Artist Rank Row
    
    @ViewBuilder
    private func artistRankRow(_ rank: MyArtistRank) -> some View {
        NavigationLink {
            ArtistLeaderboardView(artistId: rank.artistId)
        } label: {
            HStack(spacing: 12) {
                // Artist Image
                if let imageURL = rank.artistImageURL, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                }
                
                // Artist Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(rank.artistName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let myRank = rank.myRank {
                        HStack(spacing: 4) {
                            Text("You are #\(myRank)")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            
                            if let score = rank.myScore {
                                Text("• \(String(format: "%.0f", score)) pts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Not ranked yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
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

