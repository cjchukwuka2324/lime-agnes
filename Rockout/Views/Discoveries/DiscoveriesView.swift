import SwiftUI

struct DiscoveriesView: View {
    @StateObject private var viewModel = StudioSessionsViewModel.shared
    @State private var selectedTab: DiscoveriesTab = .library
    @State private var searchText = ""
    @State private var searchResults: [UserSummary] = []
    @State private var discoverFeedAlbums: [StudioAlbumRecord] = []
    @State private var isLoading = false
    @State private var isLoadingDiscoverFeed = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var showSearchSheet = false
    @FocusState private var isSearchFocused: Bool
    
    private let socialService = SupabaseSocialGraphService.shared
    private let albumService = AlbumService.shared
    
    enum DiscoveriesTab: String, CaseIterable {
        case library = "Library"
        case forYou = "For You"
    }
    
    var savedDiscoveries: [StudioAlbumRecord] {
        viewModel.discoveredAlbums
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Fixed header (always visible)
                    VStack(spacing: 0) {
                        // First row: Search button on the right
                        HStack {
                            Spacer()
                            Button {
                                showSearchSheet = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                            .padding(.trailing, 20)
                            .padding(.top, 8)
                        }
                        .frame(height: 44)
                        
                        // Second row: Discoveries title on the left
                        HStack {
                            Text("Discoveries")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.leading, 20)
                                .padding(.top, 8)
                            Spacer()
                        }
                        .frame(height: 44)
                        .background(Color.black)
                    }
                    .background(Color.black)
                    
                    // Tab Picker
                    Picker("Discoveries Tab", selection: $selectedTab) {
                        ForEach(DiscoveriesTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Content
                    if selectedTab == .library {
                        savedTabContent
                    } else {
                        forYouTabContent
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            // Load discovered albums first so isAlbumSaved works correctly
            await viewModel.loadDiscoveredAlbums()
            await loadDiscoverFeed()
        }
        .onAppear {
            // Reload discovered albums when view appears to sync any changes from detail views
            Task {
                await viewModel.loadDiscoveredAlbums()
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            searchSheetContent
        }
    }
    
    // MARK: - For You Tab Content
    
    @ViewBuilder
    private var forYouTabContent: some View {
        // Show discover feed only
        if isLoadingDiscoverFeed {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                Text("Loading discover feed...")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if discoverFeedAlbums.isEmpty {
            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.3))
                
                Text("No Albums Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Check back soon for new discoveries")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(discoverFeedAlbums) { album in
                        PublicAlbumCard(
                            album: album,
                            isSaved: viewModel.isAlbumSaved(album),
                            onAddToDiscoveries: {
                                Task {
                                    if viewModel.isAlbumSaved(album) {
                                        await viewModel.removeDiscoveredAlbum(album)
                                    } else {
                                        await viewModel.saveDiscoveredAlbum(album)
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Saved Tab Content
    
    @ViewBuilder
    private var savedTabContent: some View {
        if savedDiscoveries.isEmpty {
            VStack(spacing: 24) {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 60))
                    .foregroundColor(.white.opacity(0.3))
                
                Text("No Saved Discoveries")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Albums you save from the For You feed will appear here")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(savedDiscoveries) { album in
                        DiscoveriesAlbumCard(
                            album: album,
                            onUnsave: {
                                Task {
                                    await viewModel.removeDiscoveredAlbum(album)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Search Sheet Content
    
    @ViewBuilder
    private var searchSheetContent: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("Search by @username or email...", text: $searchText)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isSearchFocused)
                            .onChange(of: searchText) { _, newValue in
                                // Cancel previous search task
                                searchTask?.cancel()
                                
                                if newValue.isEmpty {
                                    searchResults = []
                                    errorMessage = nil
                                } else {
                                    // Debounce search by 500ms
                                    searchTask = Task {
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        if !Task.isCancelled {
                                            await performSearch(query: newValue)
                                        }
                                    }
                                }
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                                errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.15))
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    
                    // Search Results
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(.white)
                            Text("Searching...")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.red.opacity(0.6))
                            Text("Error")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !searchText.isEmpty && searchResults.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.6))
                            Text("No Users Found")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Try searching for a different @username or email")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !searchText.isEmpty {
                        // Show search results
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(searchResults) { user in
                                    NavigationLink {
                                        UserPublicAlbumsView(
                                            userId: UUID(uuidString: user.id) ?? UUID(),
                                            userName: user.displayName,
                                            userHandle: user.handle
                                        )
                                    } label: {
                                        UserSearchResultCard(user: user)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 100)
                        }
                    } else {
                        // Empty state when no search
                        VStack(spacing: 24) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.3))
                            
                            Text("Search for Users")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Find albums by searching for @username or email")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Search Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showSearchSheet = false
                        searchText = ""
                        searchResults = []
                        isSearchFocused = false
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                // Automatically focus the search field when sheet appears
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                isSearchFocused = true
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadDiscoverFeed() async {
        isLoadingDiscoverFeed = true
        defer { isLoadingDiscoverFeed = false }
        
        do {
            let albums = try await albumService.fetchDiscoverFeedAlbums(limit: 50)
            await MainActor.run {
                discoverFeedAlbums = albums
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let (users, _) = try await socialService.searchUsersPaginated(query: query, limit: 50, offset: 0)
            await MainActor.run {
                searchResults = users
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                searchResults = []
            }
        }
    }
}
