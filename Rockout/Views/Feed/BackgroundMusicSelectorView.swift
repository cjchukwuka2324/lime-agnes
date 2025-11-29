import SwiftUI

struct BackgroundMusicSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedBackgroundMusic: BackgroundMusic?
    
    @State private var searchQuery = ""
    @State private var searchResults: [SpotifyTrack] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    
    private let spotifyAPI = SpotifyAPI()
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("Search tracks...", text: $searchQuery)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit {
                                Task {
                                    await performSearch()
                                }
                            }
                        
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                                searchResults = []
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
                    .padding(.horizontal)
                    .padding(.top)
                    
                    // Search Results
                    if isSearching {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Spacer()
                    } else if !searchResults.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(searchResults) { track in
                                    trackResultRow(track: track)
                                }
                            }
                            .padding()
                        }
                    } else if let error = errorMessage {
                        Spacer()
                        VStack(spacing: 12) {
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            if error.contains("Not authenticated") {
                                Button {
                                    // Navigate to profile to connect Spotify
                                    if let url = URL(string: "rockout://profile") {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Text("Connect Spotify")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color(hex: "#1ED760"))
                                        )
                                }
                            }
                        }
                        Spacer()
                    } else if !searchQuery.isEmpty {
                        Spacer()
                        Text("No results found")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                    } else {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "music.note")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.6))
                            Text("Search for a track to play in the background")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("Background Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    private func trackResultRow(track: SpotifyTrack) -> some View {
        Button {
            selectTrack(track: track)
        } label: {
            HStack(spacing: 12) {
                if let imageURL = track.album?.imageURL {
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
                            defaultArtwork
                        @unknown default:
                            defaultArtwork
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    defaultArtwork
                        .frame(width: 60, height: 60)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(track.artists.map { $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                
                Spacer()
                
                if track.previewURL != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color(hex: "#1ED760"))
                } else {
                    Text("No preview")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var defaultArtwork: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "#1ED760").opacity(0.3),
                        Color(hex: "#1DB954").opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            )
    }
    
    private func performSearch() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            let results = try await spotifyAPI.searchTracks(query: searchQuery, limit: 20)
            searchResults = results
        } catch {
            let errorMsg = error.localizedDescription
            if errorMsg.contains("401") || errorMsg.contains("authentication") || errorMsg.contains("Not authenticated") {
                errorMessage = "Not authenticated with Spotify. Please connect your Spotify account in Profile settings."
            } else {
                errorMessage = "Search failed: \(errorMsg)"
            }
        }
    }
    
    private func selectTrack(track: SpotifyTrack) {
        // Allow selection even if there's no preview URL
        // The track info will still be stored and displayed
        let backgroundMusic = BackgroundMusic(
            spotifyId: track.id,
            name: track.name,
            artist: track.artists.first?.name ?? "Unknown Artist",
            previewURL: track.previewURL, // This is optional, so nil is fine
            imageURL: track.album?.imageURL
        )
        
        selectedBackgroundMusic = backgroundMusic
        print("✅ Selected background music: \(track.name) by \(track.artists.first?.name ?? "Unknown")")
        dismiss()
    }
}
