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
    @Environment(\.dismiss) private var dismiss

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
    
    init(album: StudioAlbumRecord, deleteContext: AlbumService.AlbumDeleteContext? = nil) {
        self.album = album
        self.deleteContext = deleteContext
        _currentAlbum = State(initialValue: album)
    }

    var body: some View {
        ZStack {
            // Background with gradient
            LinearGradient(
                colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Header with Cover Art
                    headerView
                        .padding(.top, 20)
                        .padding(.bottom, 32)
                    
                    // Tracks List
                    tracksListView
                        .padding(.horizontal, 20)
                }
            }
            .scrollContentBackground(.hidden)
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
        .task {
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
                        onDelete: {
                            Task {
                                await deleteTrack(track)
                            }
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
            tracks = try await trackService.fetchTracks(for: currentAlbum)
            print("✅ Loaded \(tracks.count) tracks for album \(currentAlbum.id.uuidString)")
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
    
    private func deleteTrack(_ track: StudioTrackRecord) async {
        do {
            try await trackService.deleteTrack(track)
            // Reload tracks to update the list
            await loadTracks()
        } catch {
            await MainActor.run {
                errorMessage = "Failed to delete track: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Track Row
struct TrackRow: View {
    let track: StudioTrackRecord
    let trackNumber: Int
    let album: StudioAlbumRecord
    let onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 16) {
            NavigationLink {
                TrackDetailView(track: track, album: album)
            } label: {
                HStack(spacing: 16) {
                    // Track Number
                    Text("\(trackNumber)")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 30, alignment: .trailing)
                    
                    // Track Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let duration = track.duration, duration > 0 {
                            Text(formatTime(duration))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    // Play Icon
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Delete Button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.8))
                    .font(.body)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .alert("Delete Track", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete \"\(track.title)\"? This action cannot be undone.")
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
}

