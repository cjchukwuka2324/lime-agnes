import SwiftUI

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showCustomDatePicker = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Loading feed…")
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
                } else if viewModel.feedItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Activity Yet")
                            .font(.headline)
                        Text("Follow users to see their RockList and StudioSessions comments here, or post a comment yourself!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if let error = viewModel.errorMessage {
                            Text("Error: \(error)")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Time Filter
                            timeFilterSection
                            
                            // Comment Input (for RockList comments)
                            if let artistId = viewModel.selectedArtistId {
                                commentInputSection(artistId: artistId)
                            }
                            
                            // Feed Items
                            ForEach(viewModel.feedItems) { item in
                                feedItemRow(item)
                                    .onTapGesture {
                                        // Allow posting comments on RockList items
                                        if item.commentType == "rocklist", let artistId = item.artistId {
                                            viewModel.selectedArtistId = artistId
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Feed")
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
                if viewModel.feedItems.isEmpty && !viewModel.isLoading {
                    viewModel.load()
                }
            }
            .sheet(isPresented: $showCustomDatePicker) {
                customDatePickerSheet
            }
        }
    }
    
    // MARK: - Time Filter Section
    
    private var timeFilterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Range")
                .font(.headline)
            
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
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Feed Item Row
    
    @ViewBuilder
    private func feedItemRow(_ item: FeedItem) -> some View {
        // Make RockList comments link to the RockList page
        if item.commentType == "rocklist", let artistId = item.artistId {
            NavigationLink {
                RockListView(artistId: artistId)
            } label: {
                feedItemContent(item)
            }
            .buttonStyle(.plain)
        } else {
            feedItemContent(item)
        }
    }
    
    @ViewBuilder
    private func feedItemContent(_ item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Comment Type Badge
                Group {
                    if item.commentType == "rocklist" {
                        Label("RockList", systemImage: "music.note.list")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    } else if item.commentType == "studio_session" {
                        Label("Studio", systemImage: "music.mic")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.2))
                            .foregroundColor(.purple)
                            .cornerRadius(8)
                    }
                }
                
                Spacer()
                
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Artist Info (for RockList comments)
            if item.commentType == "rocklist", let artistName = item.artistName {
                HStack(spacing: 12) {
                    // Artist Image
                    if let imageURL = item.artistImageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "music.note")
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("on \(artistName)'s RockList")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if item.commentType == "rocklist" {
                            HStack(spacing: 4) {
                                Text("Tap to view RockList")
                                    .font(.caption)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            
            // User Info
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.secondary)
                Text(item.displayName)
                    .font(.headline)
            }
            
            // Comment Content
            Text(item.content)
                .font(.body)
                .padding(.leading, 4)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
    
    // MARK: - Comment Input Section
    
    @ViewBuilder
    private func commentInputSection(artistId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundColor(.blue)
                Text("Post a comment")
                    .font(.headline)
            }
            
            HStack(spacing: 12) {
                TextField("Add a comment...", text: $viewModel.commentText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    .lineLimit(3...6)
                
                Button {
                    Task {
                        await viewModel.postRockListComment(artistId: artistId)
                    }
                } label: {
                    if viewModel.isPostingComment {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.blue)
                            )
                    }
                }
                .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isPostingComment)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
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

