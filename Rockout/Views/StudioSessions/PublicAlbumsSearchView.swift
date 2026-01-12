import SwiftUI

struct PublicAlbumsSearchView: View {
    @State private var searchText = ""
    @State private var searchResults: [UserSummary] = []
    @State private var discoverFeedAlbums: [StudioAlbumRecord] = []
    @State private var isLoading = false
    @State private var isLoadingDiscoverFeed = false
    @State private var errorMessage: String?
    
    private let socialService = SupabaseSocialGraphService.shared
    private let albumService = AlbumService.shared
    @StateObject private var viewModel = StudioSessionsViewModel.shared
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            // Background
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
                
                // Content
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
                } else if searchResults.isEmpty && !searchText.isEmpty {
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
                } else if searchText.isEmpty {
                    // Show discover feed albums when search is empty
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
                            VStack(alignment: .leading, spacing: 16) {
                                Text("For You")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                                
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
                                .padding(.bottom, 100)
                            }
                        }
                    }
                } else if searchResults.isEmpty {
                    VStack(spacing: 24) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))
                        
                        Text("Discover Public Albums")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Search for users by @username or email to see their public albums")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "at")
                                    .foregroundColor(.white.opacity(0.6))
                                Text("@username")
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                            }
                            
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .foregroundColor(.white.opacity(0.6))
                                Text("user@example.com")
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                        )
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
                }
            }
        }
        .task {
            // Load discovered albums first so isAlbumSaved works correctly
            await viewModel.loadDiscoveredAlbums()
            await loadDiscoverFeed()
        }
    }
    
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

// MARK: - User Search Result Card
struct UserSearchResultCard: View {
    let user: UserSummary
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Group {
                if let imageURL = user.profilePictureURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            defaultAvatar
                        @unknown default:
                            defaultAvatar
                        }
                    }
                } else {
                    defaultAvatar
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
            
            // User Info
            VStack(alignment: .leading, spacing: 6) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(user.handle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    private var defaultAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.2, green: 0.2, blue: 0.3),
                        Color(red: 0.1, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(user.avatarInitials)
                    .font(.title3.bold())
                    .foregroundColor(.white)
            )
    }
}

