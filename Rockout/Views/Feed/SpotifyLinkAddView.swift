import SwiftUI

struct SpotifyLinkAddView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedSpotifyLink: SpotifyLink?
    
    @State private var selectedTab = 0
    @State private var pastedURL = ""
    @State private var searchQuery = ""
    @State private var searchResults: [SpotifyTrack] = []
    @State private var playlistResults: [SpotifyPlaylist] = []
    @State private var isSearching = false
    @State private var isProcessingURL = false
    @State private var errorMessage: String?
    
    private let spotifyAPI = SpotifyAPI()
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("Method", selection: $selectedTab) {
                        Text("Paste Link").tag(0)
                        Text("Search").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    // Content
                    if selectedTab == 0 {
                        pasteLinkView
                    } else {
                        searchView
                    }
                }
            }
            .navigationTitle("Add Spotify Link")
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
    
    // MARK: - Paste Link View
    
    private var pasteLinkView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Paste Spotify URL")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.top)
                
                TextField("https://open.spotify.com/track/...", text: $pastedURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal)
                
                if isProcessingURL {
                    ProgressView()
                        .tint(.white)
                        .padding()
                }
                
                if let error = errorMessage {
                    VStack(spacing: 8) {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        
                        if error.contains("Not authenticated") {
                            Button {
                                // Navigate to profile to connect Spotify
                                if let url = URL(string: "rockout://profile") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Text("Connect Spotify")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(hex: "#1ED760"))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Button {
                    Task {
                        await processPastedURL()
                    }
                } label: {
                    Text("Add Link")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#1ED760"))
                        )
                }
                .disabled(pastedURL.isEmpty || isProcessingURL)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Search View
    
    private var searchView: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))
                
                TextField("Search tracks or playlists...", text: $searchQuery)
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
                        playlistResults = []
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
            } else if !searchResults.isEmpty || !playlistResults.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !searchResults.isEmpty {
                            Text("Tracks")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            ForEach(searchResults) { track in
                                trackResultRow(track: track)
                            }
                        }
                        
                        if !playlistResults.isEmpty {
                            Text("Playlists")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                                .padding(.top, searchResults.isEmpty ? 0 : 20)
                            
                            ForEach(playlistResults) { playlist in
                                playlistResultRow(playlist: playlist)
                            }
                        }
                    }
                    .padding(.vertical)
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
            }
        }
    }
    
    private func trackResultRow(track: SpotifyTrack) -> some View {
        Button {
            addTrack(track: track)
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
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    defaultArtwork
                        .frame(width: 50, height: 50)
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
            }
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func playlistResultRow(playlist: SpotifyPlaylist) -> some View {
        Button {
            addPlaylist(playlist: playlist)
        } label: {
            HStack(spacing: 12) {
                if let imageURL = playlist.imageURL {
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
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    defaultArtwork
                        .frame(width: 50, height: 50)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let owner = playlist.owner?.display_name {
                        Text("Playlist • \(owner)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var defaultArtwork: some View {
        RoundedRectangle(cornerRadius: 6)
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
    
    // MARK: - Actions
    
    private func processPastedURL() async {
        isProcessingURL = true
        errorMessage = nil
        defer { isProcessingURL = false }
        
        guard let parsed = spotifyAPI.parseSpotifyURL(pastedURL) else {
            errorMessage = "Invalid Spotify URL. Please paste a valid track or playlist link."
            return
        }
        
        do {
            if parsed.type == "track" {
                let track = try await spotifyAPI.getTrack(spotifyId: parsed.id)
                addTrack(track: track)
            } else if parsed.type == "playlist" {
                let playlist = try await spotifyAPI.getPlaylist(spotifyId: parsed.id)
                addPlaylist(playlist: playlist)
            }
        } catch {
            let errorMsg = error.localizedDescription
            if errorMsg.contains("401") || errorMsg.contains("authentication") || errorMsg.contains("Not authenticated") {
                errorMessage = "Not authenticated with Spotify. Please connect your Spotify account in Profile settings."
            } else {
                errorMessage = "Failed to load Spotify content: \(errorMsg)"
            }
        }
    }
    
    private func performSearch() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            playlistResults = []
            return
        }
        
        isSearching = true
        defer { isSearching = false }
        
        do {
            async let tracks = spotifyAPI.searchTracks(query: searchQuery, limit: 10)
            async let playlists = spotifyAPI.searchPlaylists(query: searchQuery, limit: 10)
            
            let (tracksResult, playlistsResult) = try await (tracks, playlists)
            searchResults = tracksResult
            playlistResults = playlistsResult
        } catch {
            let errorMsg = error.localizedDescription
            if errorMsg.contains("401") || errorMsg.contains("authentication") || errorMsg.contains("Not authenticated") {
                errorMessage = "Not authenticated with Spotify. Please connect your Spotify account in Profile settings."
            } else {
                errorMessage = "Search failed: \(errorMsg)"
            }
        }
    }
    
    private func addTrack(track: SpotifyTrack) {
        let spotifyLink = SpotifyLink(
            id: track.id,
            url: "https://open.spotify.com/track/\(track.id)",
            type: "track",
            name: track.name,
            artist: track.artists.first?.name,
            imageURL: track.album?.imageURL
        )
        print("✅ Adding Spotify track: \(track.name) by \(track.artists.first?.name ?? "Unknown")")
        selectedSpotifyLink = spotifyLink
        print("✅ Set selectedSpotifyLink, dismissing...")
        dismiss()
    }
    
    private func addPlaylist(playlist: SpotifyPlaylist) {
        let spotifyLink = SpotifyLink(
            id: playlist.id,
            url: "https://open.spotify.com/playlist/\(playlist.id)",
            type: "playlist",
            name: playlist.name,
            owner: playlist.owner?.display_name,
            imageURL: playlist.imageURL
        )
        print("✅ Adding Spotify playlist: \(playlist.name)")
        selectedSpotifyLink = spotifyLink
        print("✅ Set selectedSpotifyLink, dismissing...")
        dismiss()
    }
}

