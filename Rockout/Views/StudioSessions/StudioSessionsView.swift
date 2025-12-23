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
    @State private var isPublic = false
    @State private var showDiscoverSheet = false
    
    var loadingMessage: String {
        switch selectedTab {
        case .myAlbums:
            return "Loading your sessions..."
        case .sharedWithYou:
            return "Loading shared albums..."
        case .collaborations:
            return "Loading collaborations..."
        case .discoveries:
            return "Loading your discoveries..."
        }
    }
    
    enum AlbumTab: String, CaseIterable {
        case myAlbums = "My Albums"
        case sharedWithYou = "Shared with You"
        case collaborations = "Collaborations"
        case discoveries = "Discoveries"
        
        var deleteContext: AlbumService.AlbumDeleteContext? {
            switch self {
            case .myAlbums:
                return .myAlbums
            case .sharedWithYou:
                return .sharedWithYou
            case .collaborations:
                return .collaborations
            case .discoveries:
                return nil // No delete context for discoveries
            }
        }
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
        case .discoveries:
            albumsToFilter = viewModel.discoveredAlbums
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
        case .discoveries:
            return viewModel.isLoadingDiscoveredAlbums
        }
    }

    @StateObject private var playerVM = AudioPlayerViewModel.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Fixed header with title and search bar (always visible)
                    VStack(spacing: 0) {
                        // First row: Buttons on the right
                        HStack {
                            Spacer()
                            // Toolbar buttons with glassmorphism effect
                            HStack(spacing: 12) {
                                // Discover button - always visible
                                Button {
                                    showDiscoverSheet = true
                                } label: {
                                    Image(systemName: "globe")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                                
                                // Create album button - only on My Albums tab
                                if selectedTab == .myAlbums {
                                    Button {
                                        showCreateAlbumSheet = true
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .padding(.trailing, 20)
                            .padding(.top, 8)
                        }
                        .frame(height: 44)
                        
                        // Second row: StudioSessions title on the left
                        HStack {
                            Text("StudioSessions")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.leading, 20)
                                .padding(.top, 8)
                            Spacer()
                        }
                        .frame(height: 44)
                        .background(Color.black)
                        
                        // Third row: Custom search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.leading, 12)
                            
                            TextField("Search local albums...", text: $searchText)
                                .foregroundColor(.white)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.vertical, 10)
                            
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.trailing, 12)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.15))
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    }
                    .background(Color.black)
                    
                    // Custom Tab Bar
                    StudioSessionsTabBar(tabs: AlbumTab.allCases, selectedTab: $selectedTab)
                        .padding(.bottom, 16)
                    .onChange(of: selectedTab) { _, _ in
                        Task {
                            switch selectedTab {
                            case .sharedWithYou:
                                await viewModel.loadSharedAlbums()
                            case .collaborations:
                                await viewModel.loadCollaborativeAlbums()
                            case .discoveries:
                                await viewModel.loadDiscoveredAlbums()
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
                    } else if filteredAlbums.isEmpty && !isLoading {
                        emptyStateView
                    } else if !isLoading {
                        ScrollView {
                            ScrollViewOffsetReader()
                            
                            if selectedTab == .discoveries {
                                // Discoveries tab uses regular card but with unsave option
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)
                                ], spacing: 20) {
                                    ForEach(filteredAlbums) { album in
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
                            } else {
                                // Regular tabs use standard AlbumCard
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)
                                ], spacing: 20) {
                                    ForEach(filteredAlbums) { album in
                                        if let deleteContext = selectedTab.deleteContext {
                                            AlbumCard(
                                                album: album,
                                                deleteContext: deleteContext,
                                                onDelete: {
                                                    viewModel.deleteAlbum(album, context: deleteContext)
                                                }
                                            )
                                            .onTapGesture {
                                                // Navigation handled by NavigationLink in card
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .padding(.bottom, 100)
                            }
                        }
                        .detectScroll(collapseThreshold: 50)
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
            .navigationBarHidden(true)
            .onAppear {
                // Ensure navigation bar is opaque for this view
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .black
                appearance.shadowColor = .clear
                
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
                UINavigationBar.appearance().compactAppearance = appearance
            }
            .onDisappear {
                // Reset to global transparent appearance when leaving
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = UIColor.clear
                appearance.shadowColor = .clear
                
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
                UINavigationBar.appearance().compactAppearance = appearance
            }
            .sheet(isPresented: $showCreateAlbumSheet) {
                createAlbumSheet
            }
            .sheet(isPresented: $showDiscoverSheet) {
                NavigationStack {
                    PublicAlbumsSearchView()
                        .navigationTitle("Discover Albums")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(.black, for: .navigationBar)
                        .toolbarColorScheme(.dark, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showDiscoverSheet = false
                                }
                                .foregroundColor(.white)
                            }
                        }
                }
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
                    case .discoveries:
                        await viewModel.loadDiscoveredAlbums()
                    case .myAlbums:
                        break
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AcceptSharedAlbum"))) { notification in
                // Handle album acceptance from MainTabView
                if let userInfo = notification.userInfo,
                   let isCollaboration = userInfo["isCollaboration"] as? Bool {
                    Task {
                        // Reload both lists to ensure proper state
                        await viewModel.loadSharedAlbums()
                        await viewModel.loadCollaborativeAlbums()
                        
                        await MainActor.run {
                            // Navigate to the appropriate tab
                            if isCollaboration {
                                selectedTab = .collaborations
                            } else {
                                selectedTab = .sharedWithYou
                            }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMyAlbums"))) { _ in
                // Handle owner detection from MainTabView
                Task {
                    await viewModel.loadAlbums()
                    await MainActor.run {
                        selectedTab = .myAlbums
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
        case .discoveries:
            return "bookmark.fill"
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
        case .discoveries:
            return "No Discoveries"
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
        case .discoveries:
            return "Albums you save from Discover will appear here"
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
                        
                        // Public/Private Toggle
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Visibility")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text(isPublic ? "Public - Discoverable by your @username or email" : "Private - Only you and people you share with can see it")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $isPublic)
                                    .tint(.blue)
                            }
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
                        viewModel.createAlbum(title: newAlbumTitle, artistName: artistNameValue, coverArtData: imageData, isPublic: isPublic)
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
        isPublic = false
        showCreateAlbumSheet = false
    }
}

// MARK: - Album Card
struct AlbumCard: View {
    let album: StudioAlbumRecord
    let deleteContext: AlbumService.AlbumDeleteContext
    let onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
    @State private var showCollaborators = false
    @State private var showSavedUsers = false
    
    var body: some View {
        NavigationLink {
            AlbumDetailView(album: album, deleteContext: deleteContext)
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
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                
                // Album Info
                VStack(alignment: .leading, spacing: 4) {
                    // Title - full width, can wrap
                    Text(album.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    
                    // Badges row - below title
                    HStack(spacing: 8) {
                        // Public badge with saved count
                        if album.is_public == true {
                            Button {
                                showSavedUsers = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "globe")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                    if let savedCount = album.saved_count, savedCount > 0 {
                                        Text("\(savedCount)")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Collaborator/Viewer indicator
                        if let collabCount = album.collaborator_count, collabCount > 0,
                           let viewerCount = album.viewer_count, viewerCount > 0 {
                            // Both collaborators and viewers exist - show both icons
                            Button {
                                showCollaborators = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.2.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("\(collabCount)")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    
                                    Image(systemName: "eye.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("\(viewerCount)")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if let collabCount = album.collaborator_count, collabCount > 0 {
                            // Only collaborators exist
                            Button {
                                showCollaborators = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.2.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("\(collabCount)")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else if let viewerCount = album.viewer_count, viewerCount > 0 {
                            // Only viewers exist
                            Button {
                                showCollaborators = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("\(viewerCount)")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Spacer()
                    }
                    
                    if let artistName = album.artist_name, !artistName.isEmpty {
                        Text(artistName)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Album", systemImage: "trash")
            }
        }
        .alert("Delete Album", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(album.title)\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showCollaborators) {
            CollaboratorsView(albumId: album.id)
        }
        .sheet(isPresented: $showSavedUsers) {
            AlbumSavedUsersView(album: album)
        }
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


