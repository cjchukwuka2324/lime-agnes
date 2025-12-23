import SwiftUI

struct EditAlbumView: View {
    let album: StudioAlbumRecord
    let onUpdated: (StudioAlbumRecord) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var artistName: String
    @State private var coverArtImage: UIImage?
    @State private var showImagePicker = false
    @State private var tracks: [StudioTrackRecord] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isPublic: Bool
    @State private var trackToDelete: StudioTrackRecord?
    @State private var showDeleteTrackConfirmation = false
    @State private var trackTitles: [UUID: String] = [:]
    @State private var trackToEdit: StudioTrackRecord?
    @State private var showEditTrackNameSheet = false
    @State private var editedTrackName: String = ""
    
    private let albumService = AlbumService.shared
    private let trackService = TrackService.shared
    
    init(album: StudioAlbumRecord, onUpdated: @escaping (StudioAlbumRecord) -> Void) {
        self.album = album
        self.onUpdated = onUpdated
        _title = State(initialValue: album.title)
        _artistName = State(initialValue: album.artist_name ?? "")
        _isPublic = State(initialValue: album.is_public ?? false)
    }
    
    var body: some View {
        NavigationStack {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Cover Art Section
                    coverArtSection
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    
                    // Album Info Section
                    albumInfoSection
                        .padding(.horizontal, 20)
                    
                    // Tracks Reorder Section
                    if !tracks.isEmpty {
                        tracksReorderSection
                            .padding(.horizontal, 20)
                    }
                    
                    // Error Message
                    if let error = errorMessage {
                        errorView(error)
                            .padding(.horizontal, 20)
                    }
                    
                    // Save Button
                    saveButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Edit Album")
        .navigationBarTitleDisplayMode(.inline)
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
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $coverArtImage)
        }
        .task {
            await loadTracks()
            }
            .alert("Delete Track", isPresented: $showDeleteTrackConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let track = trackToDelete {
                        Task {
                            await deleteTrack(track)
                        }
                    }
                }
            } message: {
                if let track = trackToDelete {
                    Text("Are you sure you want to delete \"\(track.title)\"? This action cannot be undone.")
                }
            }
            .sheet(isPresented: $showEditTrackNameSheet) {
                editTrackNameSheet
            }
        }
    }
    
    // MARK: - Cover Art Section
    private var coverArtSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cover Art")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            
            Button {
                showImagePicker = true
            } label: {
                Group {
                    if let image = coverArtImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if let urlString = album.cover_art_url,
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
                .frame(width: 200, height: 200)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                .overlay(
                    VStack {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                        Text("Change Cover")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
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
    
    // MARK: - Album Info Section
    private var albumInfoSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Album Info")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 16) {
                // Album Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Album Title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                    
                    TextField("Enter album title", text: $title)
                        .textFieldStyle(CustomTextFieldStyle())
                }
                
                // Artist Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Artist Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                    
                    TextField("Enter artist name", text: $artistName)
                        .textFieldStyle(CustomTextFieldStyle())
                }
                
                // Public/Private Toggle
                VStack(alignment: .leading, spacing: 8) {
                    Text("Visibility")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Currently: \(isPublic ? "Public" : "Private")")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text(isPublic ? "Switch to Private - Only you and people you share with can see it" : "Switch to Public - Discoverable by your @username or email")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $isPublic)
                            .tint(.blue)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Tracks Reorder Section
    private var tracksReorderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Track Order")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            
            Text("Drag to reorder tracks")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                TrackReorderRow(
                    track: track,
                    trackNumber: index + 1,
                    displayTitle: trackTitles[track.id] ?? track.title,
                    onMoveUp: index > 0 ? {
                        withAnimation {
                            tracks.swapAt(index, index - 1)
                        }
                    } : nil,
                    onMoveDown: index < tracks.count - 1 ? {
                        withAnimation {
                            tracks.swapAt(index, index + 1)
                        }
                    } : nil,
                    onEdit: {
                        trackToEdit = track
                        editedTrackName = trackTitles[track.id] ?? track.title
                        showEditTrackNameSheet = true
                    },
                    onDelete: {
                        trackToDelete = track
                        showDeleteTrackConfirmation = true
                    }
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Save Button
    private var saveButton: some View {
        Button {
            Task {
                await saveChanges()
            }
        } label: {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                }
                Text(isSaving ? "Saving..." : "Save Changes")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if !isSaving {
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
            )
            .cornerRadius(16)
        }
        .disabled(isSaving)
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.2))
        )
    }
    
    // MARK: - Edit Track Name Sheet
    private var editTrackNameSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Track Name")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                        
                        TextField("Enter track name", text: $editedTrackName)
                            .textFieldStyle(CustomTextFieldStyle())
                    }
                    .padding(20)
                    
                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("Edit Track Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showEditTrackNameSheet = false
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if let track = trackToEdit {
                            let trimmedName = editedTrackName.trimmingCharacters(in: .whitespaces)
                            if !trimmedName.isEmpty {
                                trackTitles[track.id] = trimmedName
                            }
                        }
                        showEditTrackNameSheet = false
                    }
                    .foregroundColor(.white)
                    .disabled(editedTrackName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
    
    // MARK: - Functions
    private func loadTracks() async {
        do {
            tracks = try await trackService.fetchTracks(for: album.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func saveChanges() async {
        isSaving = true
        errorMessage = nil
        
        do {
            // Convert cover art image to data if changed
            var coverArtData: Data? = nil
            if let image = coverArtImage {
                coverArtData = image.jpegData(compressionQuality: 0.8)
            }
            
            // Update album
            let updatedAlbum = try await albumService.updateAlbum(
                album,
                title: title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title.trimmingCharacters(in: .whitespaces),
                artistName: artistName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : artistName.trimmingCharacters(in: .whitespaces),
                coverArtData: coverArtData,
                isPublic: isPublic
            )
            
            // Update track order if changed
            let trackOrder = tracks.enumerated().map { (index, track) in
                (trackId: track.id, newNumber: index + 1)
            }
            
            try await trackService.reorderTracks(albumId: album.id, trackOrder: trackOrder)
            
            // Update track titles if changed
            for track in tracks {
                if let editedTitle = trackTitles[track.id], editedTitle != track.title {
                    let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespaces)
                    if !trimmedTitle.isEmpty {
                        try await trackService.updateTrack(track, title: trimmedTitle, trackNumber: nil)
                    }
                }
            }
            
            await MainActor.run {
                onUpdated(updatedAlbum)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
    
    private func deleteTrack(_ track: StudioTrackRecord) async {
        do {
            try await trackService.deleteTrack(track)
            // Remove from local tracks array
            await MainActor.run {
                tracks.removeAll { $0.id == track.id }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to delete track: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Track Reorder Row
struct TrackReorderRow: View {
    let track: StudioTrackRecord
    let trackNumber: Int
    let displayTitle: String
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Track Number
            Text("\(trackNumber)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 30)
            
            // Track Title
            Text(displayTitle)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            // Move, Edit, and Delete Buttons
            HStack(spacing: 8) {
                if let moveUp = onMoveUp {
                    Button {
                        moveUp()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                if let moveDown = onMoveDown {
                    Button {
                        moveDown()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                
                // Edit Button
                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // Delete Button
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.8))
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

