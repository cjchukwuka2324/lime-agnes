import SwiftUI

struct StudioSessionsView: View {
    @StateObject private var viewModel = StudioSessionsViewModel()
    @EnvironmentObject var shareHandler: SharedAlbumHandler

    @State private var selectedTab: AlbumTab = .myAlbums
    @State private var newAlbumTitle = ""
    @State private var newArtistName = ""
    @State private var showCreateAlbumSheet = false
    @State private var coverArtImage: UIImage?
    @State private var showImagePicker = false
    @State private var searchText = ""
    @State private var showAcceptShareSheet = false
    @State private var shareTokenToAccept: String?
    
    var loadingMessage: String {
        switch selectedTab {
        case .myAlbums:
            return "Loading your sessions..."
        case .sharedWithYou:
            return "Loading shared albums..."
        case .collaborations:
            return "Loading collaborations..."
        }
    }
    
    enum AlbumTab: String, CaseIterable {
        case myAlbums = "My Albums"
        case sharedWithYou = "Shared with You"
        case collaborations = "Collaborations"
    }

    var filteredAlbums: [StudioAlbumRecord] {
        let albumsToFilter: [StudioAlbumRecord]
        switch selectedTab {
        case .myAlbums:
            albumsToFilter = viewModel.albums
        case .sharedWithYou:
            albumsToFilter = viewModel.sharedAlbums
        case .collaborations:
            albumsToFilter = viewModel.collaborativeAlbums
        }
        
        if searchText.isEmpty {
            return albumsToFilter
        }
        return albumsToFilter.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    var isLoading: Bool {
        switch selectedTab {
        case .myAlbums:
            return viewModel.isLoadingAlbums
        case .sharedWithYou:
            return viewModel.isLoadingSharedAlbums
        case .collaborations:
            return viewModel.isLoadingCollaborativeAlbums
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("Album Tab", selection: $selectedTab) {
                        ForEach(AlbumTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .onChange(of: selectedTab) { _, _ in
                        Task {
                            switch selectedTab {
                            case .sharedWithYou:
                                await viewModel.loadSharedAlbums()
                            case .collaborations:
                                await viewModel.loadCollaborativeAlbums()
                            case .myAlbums:
                                break
                            }
                        }
                    }
                    
                    // Content
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .tint(.white)
                            Text(loadingMessage)
                                .foregroundColor(.white.opacity(0.7))
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredAlbums.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ], spacing: 20) {
                                ForEach(filteredAlbums) { album in
                                    AlbumCard(album: album)
                                        .onTapGesture {
                                            // Navigation handled by NavigationLink in card
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 100)
                        }
                    }
                }
                
                // Error Banner
                if let error = viewModel.errorMessage {
                    VStack {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.white)
                                .font(.subheadline)
                        }
                        .padding()
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .padding(.top, 60)
                        Spacer()
                    }
                }
            }
            .navigationTitle("Studio Sessions")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                // Ensure navigation bar is always opaque
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .black
                appearance.shadowColor = .clear
                
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
                UINavigationBar.appearance().compactAppearance = appearance
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedTab == .myAlbums {
                        Button {
                            showCreateAlbumSheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search albums...")
            .sheet(isPresented: $showCreateAlbumSheet) {
                createAlbumSheet
            }
            .onAppear {
                viewModel.loadAlbums()
                // Load appropriate albums based on selected tab
                Task {
                    switch selectedTab {
                    case .sharedWithYou:
                        await viewModel.loadSharedAlbums()
                    case .collaborations:
                        await viewModel.loadCollaborativeAlbums()
                    case .myAlbums:
                        break
                    }
                }
            }
            .onChange(of: shareHandler.shouldShowAcceptSheet) { _, shouldShow in
                if shouldShow, let token = shareHandler.pendingShareToken {
                    shareTokenToAccept = token
                    showAcceptShareSheet = true
                    shareHandler.shouldShowAcceptSheet = false
                }
            }
            .sheet(isPresented: $showAcceptShareSheet) {
                if let token = shareTokenToAccept {
                    AcceptSharedAlbumView(shareToken: token) {
                        // Reload shared albums after accepting
                        Task {
                            await viewModel.loadSharedAlbums()
                            selectedTab = .sharedWithYou
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            
            Text(emptyStateTitle)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if selectedTab == .myAlbums {
                Button {
                    showCreateAlbumSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Album")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(25)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var emptyStateIcon: String {
        switch selectedTab {
        case .myAlbums:
            return "music.note.list"
        case .sharedWithYou:
            return "person.2.fill"
        case .collaborations:
            return "person.3.fill"
        }
    }
    
    var emptyStateTitle: String {
        switch selectedTab {
        case .myAlbums:
            return "No Albums Yet"
        case .sharedWithYou:
            return "No Shared Albums"
        case .collaborations:
            return "No Collaborations"
        }
    }
    
    var emptyStateMessage: String {
        switch selectedTab {
        case .myAlbums:
            return "Create your first album to start organizing your music"
        case .sharedWithYou:
            return "Albums shared with you will appear here"
        case .collaborations:
            return "Albums you're collaborating on will appear here"
        }
    }
    
    // MARK: - Create Album Sheet
    private var createAlbumSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Cover Art Preview
                        VStack(spacing: 16) {
                            if let image = coverArtImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 200, height: 200)
                                    .cornerRadius(20)
                                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.2)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 200, height: 200)
                                    
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text("Cover Art")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                            }
                            
                            Button {
                                showImagePicker = true
                            } label: {
                                HStack {
                                    Image(systemName: coverArtImage == nil ? "photo.badge.plus" : "photo.badge.arrow.forward")
                                    Text(coverArtImage == nil ? "Add Cover Art" : "Change Cover Art")
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(25)
                            }
                        }
                        .padding(.top, 20)
                        
                        // Album Title
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Album Title")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextField("Enter album title", text: $newAlbumTitle)
                                .textFieldStyle(.plain)
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 24)
                        
                        // Artist Name
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Artist Name")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextField("Enter artist name (optional)", text: $newArtistName)
                                .textFieldStyle(.plain)
                                .font(.title3)
                                .foregroundColor(.white)
                                .autocapitalization(.words)
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        resetAlbumCreation()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        let imageData = coverArtImage?.jpegData(compressionQuality: 0.8)
                        let artistNameValue = newArtistName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newArtistName.trimmingCharacters(in: .whitespaces)
                        viewModel.createAlbum(title: newAlbumTitle, artistName: artistNameValue, coverArtData: imageData)
                        resetAlbumCreation()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                    .disabled(newAlbumTitle.isEmpty)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $coverArtImage)
            }
        }
    }

    private func resetAlbumCreation() {
        newAlbumTitle = ""
        newArtistName = ""
        coverArtImage = nil
        showCreateAlbumSheet = false
    }
}

// MARK: - Album Card
struct AlbumCard: View {
    let album: StudioAlbumRecord
    
    var body: some View {
        NavigationLink {
            AlbumDetailView(album: album)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Cover Art
                Group {
                    if let urlString = album.cover_art_url,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                albumPlaceholder
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                albumPlaceholder
                            @unknown default:
                                albumPlaceholder
                            }
                        }
                    } else {
                        albumPlaceholder
                    }
                }
                .frame(width: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                
                // Album Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let artistName = album.artist_name, !artistName.isEmpty {
                        Text(artistName)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    if let status = album.release_status, !status.isEmpty {
                        Text(status.capitalized)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var albumPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

