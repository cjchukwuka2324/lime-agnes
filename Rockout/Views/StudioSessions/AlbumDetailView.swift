import SwiftUI

struct AlbumDetailView: View {
    let album: StudioAlbumRecord

    @State private var tracks: [StudioTrackRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddTrack = false
    @State private var showShare = false
    @State private var showEditAlbum = false
    @State private var currentAlbum: StudioAlbumRecord

    private let trackService = TrackService.shared
    
    init(album: StudioAlbumRecord) {
        self.album = album
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
        }
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
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    showEditAlbum = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.white)
                }
                
                Button {
                    showShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.white)
                }
                
                Button {
                    showAddTrack = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheetView(resourceType: "album", resourceId: album.id)
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
                    TrackRow(track: track, trackNumber: track.track_number ?? (index + 1), album: currentAlbum)
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
}

// MARK: - Track Row
struct TrackRow: View {
    let track: StudioTrackRecord
    let trackNumber: Int
    let album: StudioAlbumRecord
    
    var body: some View {
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
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
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

