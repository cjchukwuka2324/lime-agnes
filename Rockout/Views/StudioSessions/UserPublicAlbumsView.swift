import SwiftUI

struct UserPublicAlbumsView: View {
    let userId: UUID
    let userName: String
    let userHandle: String
    
    @State private var publicAlbums: [StudioAlbumRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @StateObject private var viewModel = StudioSessionsViewModel.shared
    
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
        .navigationTitle(userName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            loadPublicAlbums()
            Task {
                await viewModel.loadDiscoveredAlbums() // Load saved albums to check which are already saved
            }
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

