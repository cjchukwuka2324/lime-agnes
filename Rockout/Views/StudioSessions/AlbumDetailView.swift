import SwiftUI

struct AlbumDetailView: View {
    let album: StudioAlbumRecord
    let deleteContext: AlbumService.AlbumDeleteContext?

    @State private var tracks: [StudioTrackRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddTrack = false
    @State private var showShare = false
    @State private var showEditAlbum = false
    @State private var showDeleteAlbumConfirmation = false
    @State private var showLeaveCollaborationConfirmation = false
    @State private var showDeleteOptions = false
    @State private var currentAlbum: StudioAlbumRecord
    @State private var showPlayBreakdown = false
    @State private var selectedTrackForBreakdown: StudioTrackRecord?
    @State private var showSavedUsers = false
    @State private var isAlbumSaved = false
    @State private var currentUserId: UUID?
    @State private var showSaveConfirmation = false
    @State private var saveConfirmationMessage = ""
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerVM = AudioPlayerViewModel.shared
    @StateObject private var viewModel = StudioSessionsViewModel()

    private let trackService = TrackService.shared
    private let albumService = AlbumService.shared
    
    // Check if this is a collaboration context
    private var isCollaboration: Bool {
        return deleteContext == .collaborations
    }
    
    // Check if this is a view-only share (shared with you)
    private var isViewOnly: Bool {
        return deleteContext == .sharedWithYou
    }
    
    // Check if user can see play counts (owner or collaborator)
    private var canViewPlayCounts: Bool {
        // View-only users cannot see play counts
        if deleteContext == .sharedWithYou {
            return false
        }
        // Explicit contexts: myAlbums and collaborations always allow play counts
        if deleteContext == .myAlbums || deleteContext == .collaborations {
            return true
        }
        // If deleteContext is nil (public albums from discover), only show if user is owner
        // Public viewers should NOT see play counts
        if deleteContext == nil {
            return isOwner
        }
        // Default: deny access
        return false
    }
    
    // Check if user is album owner
    private var isOwner: Bool {
        guard let currentUserId = currentUserId else { return false }
        return currentUserId == album.artist_id
    }
    
    // Check if user can delete album
    private var canDeleteAlbum: Bool {
        // Cannot delete discovered albums (public albums from discover)
        if deleteContext == nil && !isOwner {
            return false
        }
        // Can delete if it's in myAlbums or collaborations context
        if deleteContext == .myAlbums || deleteContext == .collaborations {
            return true
        }
        // Can delete if user is owner (even in other contexts)
        if isOwner {
            return true
        }
        // Default: cannot delete
        return false
    }
    
    // Check if user is owner or collaborator (can see analytics)
    private var canViewAnalytics: Bool {
        return isOwner || isCollaboration || (deleteContext == .myAlbums)
    }
    
    init(album: StudioAlbumRecord, deleteContext: AlbumService.AlbumDeleteContext? = nil) {
        self.album = album
        self.deleteContext = deleteContext
        _currentAlbum = State(initialValue: album)
    }

    var body: some View {
        ZStack {
            // Background - solid black
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header with Cover Art
                    headerView
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                    
                    // Tracks List
                    tracksListView
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100) // Space for bottom player bar
                }
            }
            .scrollContentBackground(.hidden)
            
            // Save Confirmation Toast
            if showSaveConfirmation {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        Text(saveConfirmationMessage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.15))
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                            )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(1000)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .background(Color.black)
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
        .onDisappear {
            // Reset to global appearance when leaving
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.black
            appearance.shadowColor = .clear
            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Only show edit and add track buttons if not view-only
                if !isViewOnly {
                    Button {
                        showEditAlbum = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(.white)
                    }
                    
                    Button {
                        showAddTrack = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                    }
                }
                
                // Share button is always available (but view-only albums can only share as view-only)
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.white)
                }
                
                // Saved users analytics button (only for owners/collaborators and public albums)
                if canViewAnalytics && album.is_public == true {
                    Button {
                        showSavedUsers = true
                    } label: {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.white)
                    }
                }
                
                // Save/Unsave button for Discover context (if not owner and public album)
                if deleteContext == nil && !isOwner && album.is_public == true {
                    Button {
                        Task {
                            let wasSaved = isAlbumSaved
                            
                            if wasSaved {
                                await viewModel.removeDiscoveredAlbum(album)
                            } else {
                                await viewModel.saveDiscoveredAlbum(album)
                            }
                            
                            // Update saved state after operation
                            isAlbumSaved = viewModel.isAlbumSaved(album)
                            
                            // Check if operation succeeded (state changed as expected)
                            if isAlbumSaved != wasSaved {
                                // Success - show confirmation
                                saveConfirmationMessage = wasSaved ? "Removed from Discoveries" : "Saved to Discoveries"
                            } else {
                                // Failed - show error
                                saveConfirmationMessage = viewModel.errorMessage ?? "Failed to update. Please try again."
                            }
                            
                            // Show confirmation
                            withAnimation(.spring(response: 0.3)) {
                                showSaveConfirmation = true
                            }
                            
                            // Hide confirmation after 2 seconds
                            try? await Task.sleep(for: .seconds(2))
                            
                            withAnimation(.spring(response: 0.3)) {
                                showSaveConfirmation = false
                            }
                        }
                    } label: {
                        Image(systemName: isAlbumSaved ? "bookmark.fill" : "bookmark")
                            .foregroundColor(.white)
                    }
                }
                
                // Only show delete menu if user can delete (not for discovered albums)
                if canDeleteAlbum {
                    Menu {
                        if isCollaboration {
                            // For collaborations, show both options
                            Button {
                                showLeaveCollaborationConfirmation = true
                            } label: {
                                Label("Leave Collaboration", systemImage: "person.2.slash")
                            }
                            
                            Button(role: .destructive) {
                                showDeleteAlbumConfirmation = true
                            } label: {
                                Label("Delete Album", systemImage: "trash")
                            }
                        } else {
                            // For other contexts, just show delete
                            Button(role: .destructive) {
                                showDeleteAlbumConfirmation = true
                            } label: {
                                Label("Delete Album", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .alert("Leave Collaboration", isPresented: $showLeaveCollaborationConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                Task {
                    await leaveCollaboration()
                }
            }
        } message: {
            Text("Are you sure you want to leave the collaboration for \"\(currentAlbum.title)\"? You will no longer be able to edit this album, but it will remain for other collaborators.")
        }
        .alert("Delete Album", isPresented: $showDeleteAlbumConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteAlbumCompletely()
                }
            }
        } message: {
            let message = deleteMessage(for: currentAlbum)
            Text(message)
        }
        .sheet(isPresented: $showShare) {
            ShareSheetView(
                resourceType: "album",
                resourceId: album.id,
                allowCollaboration: !isViewOnly
            )
        }
        .sheet(isPresented: $showAddTrack) {
            AddTrackView(album: currentAlbum) {
                Task { await loadTracks() }
            }
        }
        .sheet(isPresented: $showEditAlbum) {
            EditAlbumView(album: currentAlbum) { updatedAlbum in
                currentAlbum = updatedAlbum
                Task { await loadTracks() }
            }
        }
        .sheet(isPresented: $showPlayBreakdown) {
            if let track = selectedTrackForBreakdown {
                TrackPlayBreakdownView(track: track, album: currentAlbum)
            }
        }
        .sheet(isPresented: $showSavedUsers) {
            AlbumSavedUsersView(album: currentAlbum)
        }
        .task {
            // Get current user ID
            do {
                let session = try await SupabaseService.shared.client.auth.session
                currentUserId = session.user.id
            } catch {
                print("⚠️ Could not get current user ID: \(error.localizedDescription)")
            }
            
            // Check if album is saved (for Discover context)
            if deleteContext == nil && !isOwner {
                // Load discovered albums first to ensure accurate state
                await viewModel.loadDiscoveredAlbums()
                isAlbumSaved = viewModel.isAlbumSaved(album)
            }
            
            await loadTracks()
            // Refresh album data to get latest changes (important for collaborations)
            await refreshAlbum()
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        VStack(spacing: 20) {
            // Cover Art
            Group {
                if let urlString = currentAlbum.cover_art_url,
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
            .frame(width: 240, height: 240)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
            
            // Album Info
            VStack(spacing: 8) {
                Text(currentAlbum.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                if let artistName = currentAlbum.artist_name, !artistName.isEmpty {
                    Text(artistName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                if let status = currentAlbum.release_status, !status.isEmpty {
                    Text(status.capitalized)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 24)
    }
    
    private var albumPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
        }
    }
    
    // MARK: - Tracks List View
    private var tracksListView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tracks")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                if !tracks.isEmpty {
                    Text("\(tracks.count)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                        .padding(.vertical, 40)
                    Spacer()
                }
            } else if tracks.isEmpty {
                emptyTracksView
            } else {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    TrackRow(
                        track: track,
                        trackNumber: track.track_number ?? (index + 1),
                        album: currentAlbum,
                        tracks: tracks,
                        showPlayCount: canViewPlayCounts,
                        onShowPlayBreakdown: {
                            selectedTrackForBreakdown = track
                            showPlayBreakdown = true
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Empty Tracks View
    private var emptyTracksView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No tracks yet")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            
            Text("Add your first track to get started")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            
            if !isViewOnly {
                Button {
                    showAddTrack = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Track")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .cornerRadius(25)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func loadTracks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Include play counts if user is owner or collaborator
            let includeCounts = canViewPlayCounts
            tracks = try await trackService.fetchTracks(for: currentAlbum, includePlayCounts: includeCounts)
            print("✅ Loaded \(tracks.count) tracks for album \(currentAlbum.id.uuidString), includePlayCounts: \(includeCounts)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading tracks: \(error.localizedDescription)")
        }
    }
    
    private func refreshAlbum() async {
        do {
            // Fetch the latest album data from the database
            let updatedAlbum = try await albumService.fetchAlbum(albumId: currentAlbum.id)
            
            await MainActor.run {
                currentAlbum = updatedAlbum
            }
            print("✅ Refreshed album data for \(currentAlbum.id.uuidString)")
        } catch {
            print("⚠️ Failed to refresh album: \(error.localizedDescription)")
            // Don't show error to user - just log it, as the initial album data is still valid
        }
    }
    
    private func deleteAlbumCompletely() async {
        do {
            if let context = deleteContext {
                try await albumService.deleteAlbumCompletely(currentAlbum, context: context)
            } else {
                // Auto-detect context - default to complete deletion
                try await albumService.deleteAlbum(currentAlbum)
            }
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to delete album: \(error.localizedDescription)"
            }
        }
    }
    
    private func leaveCollaboration() async {
        do {
            try await albumService.leaveCollaboration(album: currentAlbum)
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to leave collaboration: \(error.localizedDescription)"
            }
        }
    }
    
    private func deleteMessage(for album: StudioAlbumRecord) -> String {
        guard let context = deleteContext else {
            return "Are you sure you want to delete \"\(album.title)\"? This action cannot be undone."
        }
        
        switch context {
        case .myAlbums:
            return "Are you sure you want to delete \"\(album.title)\"? This will permanently delete the album and all its tracks. This action cannot be undone."
        case .sharedWithYou:
            return "Are you sure you want to remove \"\(album.title)\" from your library? The original album will remain with its owner."
        case .collaborations:
            return "Are you sure you want to delete \"\(album.title)\"? This will permanently delete the album and all contributions for all collaborators. This action cannot be undone."
        }
    }
    
}

// MARK: - Track Row
struct TrackRow: View {
    let track: StudioTrackRecord
    let trackNumber: Int
    let album: StudioAlbumRecord
    let tracks: [StudioTrackRecord]
    let showPlayCount: Bool
    let onShowPlayBreakdown: () -> Void
    
    @StateObject private var playerVM = AudioPlayerViewModel.shared
    
    private var isCurrentlyPlaying: Bool {
        playerVM.currentTrack?.id == track.id && playerVM.isPlaying
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Album Cover Art (same as album)
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
            .frame(width: 50, height: 50)
            .cornerRadius(8)
            
            // Track Info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    if let duration = track.duration, duration > 0 {
                        Text(formatTime(duration))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    // Play count (only show if available and user can view)
                    if showPlayCount, let playCount = track.play_count, playCount > 0 {
                        Button {
                            onShowPlayBreakdown()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.circle.fill")
                                    .font(.caption2)
                                Text("\(formatPlayCount(playCount)) play\(playCount == 1 ? "" : "s")")
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if isCurrentlyPlaying {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.caption2)
                            Text("Now Playing")
                                .font(.caption2)
                        }
                        .foregroundColor(.green)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Play/Pause Button
            Button {
                if isCurrentlyPlaying {
                    playerVM.pause()
                } else {
                    // Load track - it will auto-play when ready
                    playerVM.loadTrack(track, album: album, tracks: tracks)
                }
            } label: {
                Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundColor(isCurrentlyPlaying ? .green : .white.opacity(0.6))
            }
        }
        .contentShape(Rectangle()) // Make entire row tappable
        .onTapGesture {
            // Play on tap anywhere on the row (except buttons)
            if !isCurrentlyPlaying {
                // Load track - it will auto-play when ready
                playerVM.loadTrack(track, album: album, tracks: tracks)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(isCurrentlyPlaying ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var albumPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.3))
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        guard time.isFinite && !time.isNaN else {
            return "0:00"
        }
        
        let validTime = max(0, time)
        let minutes = Int(validTime) / 60
        let seconds = Int(validTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatPlayCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}

