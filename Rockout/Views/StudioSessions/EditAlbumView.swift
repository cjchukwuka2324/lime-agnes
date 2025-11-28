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
    
    private let albumService = AlbumService.shared
    private let trackService = TrackService.shared
    
    init(album: StudioAlbumRecord, onUpdated: @escaping (StudioAlbumRecord) -> Void) {
        self.album = album
        self.onUpdated = onUpdated
        _title = State(initialValue: album.title)
        _artistName = State(initialValue: album.artist_name ?? "")
    }
    
    var body: some View {
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
            ToolbarItem(placement: .navigationBarLeading) {
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
                    onMoveUp: index > 0 ? {
                        withAnimation {
                            tracks.swapAt(index, index - 1)
                        }
                    } : nil,
                    onMoveDown: index < tracks.count - 1 ? {
                        withAnimation {
                            tracks.swapAt(index, index + 1)
                        }
                    } : nil
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
                coverArtData: coverArtData
            )
            
            // Update track order if changed
            let trackOrder = tracks.enumerated().map { (index, track) in
                (trackId: track.id, newNumber: index + 1)
            }
            
            try await trackService.reorderTracks(albumId: album.id, trackOrder: trackOrder)
            
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
}

// MARK: - Track Reorder Row
struct TrackReorderRow: View {
    let track: StudioTrackRecord
    let trackNumber: Int
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 16) {
            // Track Number
            Text("\(trackNumber)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 30)
            
            // Track Title
            Text(track.title)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            // Move Buttons
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
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

