import SwiftUI

struct UserPublicAlbumsView: View {
    let userId: UUID
    let userName: String
    let userHandle: String
    
    @State private var publicAlbums: [StudioAlbumRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @StateObject private var viewModel = StudioSessionsViewModel()
    
    private let albumService = AlbumService.shared
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading albums...")
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
            } else if publicAlbums.isEmpty {
                VStack(spacing: 24) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text("No Public Albums")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("\(userName) hasn't made any albums public yet")
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
                    ], spacing: 20) {
                        ForEach(publicAlbums) { album in
                            PublicAlbumCard(
                                album: album,
                                isSaved: viewModel.isAlbumSaved(album),
                                onAddToDiscoveries: {
                                    viewModel.saveDiscoveredAlbum(album)
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
        .navigationTitle(userName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            loadPublicAlbums()
            viewModel.loadDiscoveredAlbums() // Load saved albums to check which are already saved
        }
    }
    
    private func loadPublicAlbums() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            
            do {
                let albums = try await albumService.fetchPublicAlbumsByUserId(userId: userId)
                await MainActor.run {
                    publicAlbums = albums
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Public Album Card
struct PublicAlbumCard: View {
    let album: StudioAlbumRecord
    let isSaved: Bool
    let onAddToDiscoveries: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover Art with Add button overlay
            ZStack(alignment: .topTrailing) {
                NavigationLink {
                    AlbumDetailView(album: album, deleteContext: nil)
                } label: {
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
                }
                .buttonStyle(PlainButtonStyle())
                
                // Add to Discoveries button
                if !isSaved {
                    Button {
                        onAddToDiscoveries()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption)
                            Text("Add to Discoveries")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(16)
                    }
                    .padding(8)
                } else {
                    // Already saved indicator
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Saved")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(16)
                    .padding(8)
                }
            }
            
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
                
                // Public indicator
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("Public")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.top, 2)
            }
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

