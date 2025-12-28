import SwiftUI

struct SpotifyLinkAddView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedSpotifyLink: SpotifyLink?
    
    // Paste URL state
    @State private var pastedURL = ""
    @State private var isProcessingURL = false
    @State private var showPasteSheet = false
    
    // Search state
    @State private var selectedPlatform = 0 // 0 = Spotify, 1 = Apple Music
    @State private var searchQuery = ""
    @State private var spotifyTracks: [SpotifyTrack] = []
    @State private var spotifyPlaylists: [SpotifyPlaylist] = []
    @State private var appleMusicSongs: [AppleMusicWebAPISong] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    
    private let spotifyAPI = SpotifyAPI()
    private let appleMusicAPI = AppleMusicWebAPI.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                searchView
            }
            .navigationTitle("Add Music Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showPasteSheet = true
                    } label: {
                        Image(systemName: "link")
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showPasteSheet) {
                pasteLinkSheet
            }
        }
    }
    
    // MARK: - Paste Link Sheet
    
    private var pasteLinkSheet: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Instructions
                        VStack(spacing: 12) {
                            Image(systemName: "link")
                                .font(.system(size: 48))
                                .foregroundColor(Color(hex: "#1ED760"))
                            
                            Text("Paste Music Link")
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            
                            Text("Paste a Spotify or Apple Music link")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        
                        // URL Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Music Link")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            TextField("https://open.spotify.com/track/... or https://music.apple.com/...", text: $pastedURL, axis: .vertical)
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
                            
                            // Supported platforms hint
                            HStack(spacing: 16) {
                                Label("Spotify", systemImage: "music.note")
                                Label("Apple Music", systemImage: "music.note")
                            }
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        }
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
                                    .padding(.horizontal)
                            }
                        }
                        
                        // Add Button
                        Button {
                            Task {
                                await processPastedURL()
                                if selectedSpotifyLink != nil {
                                    showPasteSheet = false
                                    dismiss()
                                }
                            }
                        } label: {
                            Text("Add Link")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(canAddLink ? Color(hex: "#1ED760") : Color.white.opacity(0.3))
                                )
                        }
                        .disabled(!canAddLink || isProcessingURL)
                        .padding(.horizontal)
                        
                        Spacer()
                            .frame(height: 40)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Paste Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showPasteSheet = false
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    // MARK: - Search View
    
    private var searchView: some View {
        VStack(spacing: 0) {
            // Top controls pinned at top
            VStack(spacing: 12) {
                // Platform selector
                Picker("Platform", selection: $selectedPlatform) {
                    Text("Spotify").tag(0)
                    Text("Apple Music").tag(1)
                }
                .pickerStyle(.segmented)

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
                            clearSearchResults()
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
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Results/content fill the rest so controls stay at top
            Group {
                if isSearching {
                    VStack { Spacer(); ProgressView().tint(.white); Spacer() }
                } else if hasSearchResults {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if selectedPlatform == 0 {
                                // Spotify results
                                if !spotifyTracks.isEmpty {
                                    Text("Tracks")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.horizontal)

                                    ForEach(spotifyTracks) { track in
                                        spotifyTrackRow(track: track)
                                    }
                                }

                                if !spotifyPlaylists.isEmpty {
                                    Text("Playlists")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.horizontal)
                                        .padding(.top, spotifyTracks.isEmpty ? 0 : 20)

                                    ForEach(spotifyPlaylists) { playlist in
                                        spotifyPlaylistRow(playlist: playlist)
                                    }
                                }
                            } else {
                                // Apple Music results
                                if !appleMusicSongs.isEmpty {
                                    Text("Songs")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(.horizontal)

                                    ForEach(appleMusicSongs) { song in
                                        appleMusicSongRow(song: song)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                } else if !searchQuery.isEmpty && !isSearching {
                    VStack(spacing: 12) {
                        if let error = errorMessage {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title2)
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)

                                if error.contains("connect your Spotify account") {
                                    Button {
                                        dismiss()
                                    } label: {
                                        HStack {
                                            Image(systemName: "link")
                                            Text("Connect Spotify")
                                        }
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color(hex: "#1ED760"))
                                        .cornerRadius(8)
                                    }
                                    .padding(.top, 8)
                                }
                            }
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.5))
                                Text("No results found")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Try a different search term")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Idle state filler to keep controls at top
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Search Result Rows
    
    private func spotifyTrackRow(track: SpotifyTrack) -> some View {
        Button {
            addSpotifyTrack(track: track)
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
    
    private func spotifyPlaylistRow(playlist: SpotifyPlaylist) -> some View {
        Button {
            addSpotifyPlaylist(playlist: playlist)
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
    
    private func appleMusicSongRow(song: AppleMusicWebAPISong) -> some View {
        Button {
            addAppleMusicSong(song: song)
        } label: {
            HStack(spacing: 12) {
                if let artwork = song.attributes.artwork {
                    let imageURL = URL(string: artwork.urlForSize(width: 100, height: 100))
                    if let imageURL = imageURL {
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
                } else {
                    defaultArtwork
                        .frame(width: 50, height: 50)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.attributes.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(song.attributes.artistName)
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
    
    // MARK: - Computed Properties
    
    private var canAddLink: Bool {
        !pastedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var hasSearchResults: Bool {
        if selectedPlatform == 0 {
            return !spotifyTracks.isEmpty || !spotifyPlaylists.isEmpty
        } else {
            return !appleMusicSongs.isEmpty
        }
    }
    
    // MARK: - Actions
    
    private func clearSearchResults() {
        spotifyTracks = []
        spotifyPlaylists = []
        appleMusicSongs = []
        errorMessage = nil
    }
    
    private func performSearch() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            clearSearchResults()
            return
        }
        
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        
        do {
            if selectedPlatform == 0 {
                // Spotify search
                print("🔍 Searching Spotify for: '\(searchQuery)'")
                async let tracks = spotifyAPI.searchTracksPublic(query: searchQuery, limit: 10)
                async let playlists = spotifyAPI.searchPlaylistsPublic(query: searchQuery, limit: 10)
                
                let (tracksResult, playlistsResult) = try await (tracks, playlists)
                
                print("✅ Spotify search completed: \(tracksResult.count) tracks, \(playlistsResult.count) playlists")
                
                await MainActor.run {
                    spotifyTracks = tracksResult
                    spotifyPlaylists = playlistsResult
                    
                    // If both are empty, show a helpful message
                    if tracksResult.isEmpty && playlistsResult.isEmpty {
                        errorMessage = "No results found. Try a different search term."
                    } else {
                        errorMessage = nil
                    }
                }
            } else {
                // Apple Music search
                print("🔍 Searching Apple Music for: '\(searchQuery)'")
                let response = try await appleMusicAPI.searchPublic(query: searchQuery, types: ["songs"], limit: 20)
                
                print("✅ Apple Music search completed: \(response.results.songs?.data.count ?? 0) songs")
                
                await MainActor.run {
                    appleMusicSongs = response.results.songs?.data ?? []
                    
                    // If empty, show a helpful message
                    if appleMusicSongs.isEmpty {
                        errorMessage = "No results found. Try a different search term."
                    } else {
                        errorMessage = nil
                    }
                }
            }
        } catch {
            print("❌ Search error: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ Error userInfo: \(nsError.userInfo)")
            }
            
            await MainActor.run {
                // Provide more helpful error messages
                let errorDesc = error.localizedDescription
                if errorDesc.contains("Client secret not configured") || errorDesc.contains("client secret") {
                    errorMessage = "Spotify search requires configuration. Add your client secret to Secrets.swift. See console for details."
                } else if errorDesc.contains("Permission denied") || errorDesc.contains("MusicKit") || errorDesc.contains("authorization") {
                    if selectedPlatform == 1 {
                        errorMessage = "Apple Music access is required. Please allow access when prompted, or enable it in Settings > RockOut > Media & Apple Music."
                    } else {
                        errorMessage = "Permission denied. Please check your settings."
                    }
                } else if errorDesc.contains("401") || errorDesc.contains("Authentication") {
                    errorMessage = "Authentication failed. Please try again."
                } else if errorDesc.contains("429") {
                    errorMessage = "Too many requests. Please wait a moment and try again."
                } else {
                    errorMessage = "Search failed: \(errorDesc)"
                }
                clearSearchResults()
            }
        }
    }
    
    private func addSpotifyTrack(track: SpotifyTrack) {
        let spotifyLink = SpotifyLink(
            id: track.id,
            url: "https://open.spotify.com/track/\(track.id)",
            type: "track",
            name: track.name,
            artist: track.artists.first?.name,
            imageURL: track.album?.imageURL
        )
        selectedSpotifyLink = spotifyLink
        dismiss()
    }
    
    private func addSpotifyPlaylist(playlist: SpotifyPlaylist) {
        let spotifyLink = SpotifyLink(
            id: playlist.id,
            url: "https://open.spotify.com/playlist/\(playlist.id)",
            type: "playlist",
            name: playlist.name,
            owner: playlist.owner?.display_name,
            imageURL: playlist.imageURL
        )
        selectedSpotifyLink = spotifyLink
        dismiss()
    }
    
    private func addAppleMusicSong(song: AppleMusicWebAPISong) {
        // Get URL from song attributes or construct it
        let url = song.attributes.url ?? "https://music.apple.com/song/\(song.id)"
        
        let spotifyLink = SpotifyLink(
            id: song.id,
            url: url,
            type: "track",
            name: song.attributes.name,
            artist: song.attributes.artistName,
            imageURL: song.attributes.artwork.flatMap { 
                URL(string: $0.urlForSize(width: 300, height: 300))
            }
        )
        selectedSpotifyLink = spotifyLink
        dismiss()
    }
    
    // MARK: - URL Parsing & Processing
    
    private func processPastedURL() async {
        isProcessingURL = true
        errorMessage = nil
        defer { isProcessingURL = false }
        
        let trimmedURL = pastedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Parse Spotify URL
        if let spotifyLink = parseSpotifyURL(trimmedURL) {
            selectedSpotifyLink = spotifyLink
            dismiss()
            return
        }
        
        // Parse Apple Music URL
        if let appleMusicLink = parseAppleMusicURL(trimmedURL) {
            selectedSpotifyLink = appleMusicLink
            dismiss()
            return
        }
        
        errorMessage = "Invalid music link. Please paste a valid Spotify or Apple Music URL."
    }
    
    private func parseSpotifyURL(_ urlString: String) -> SpotifyLink? {
        let urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle spotify: URI scheme
        if urlString.hasPrefix("spotify:") {
            let components = urlString.split(separator: ":")
            if components.count >= 3 {
                let type = String(components[1]) // track or playlist
                let id = String(components[2])
                if type == "track" || type == "playlist" {
                    let url = "https://open.spotify.com/\(type)/\(id)"
                    return SpotifyLink(
                        id: id,
                        url: url,
                        type: type,
                        name: type == "track" ? "Track" : "Playlist",
                        artist: nil,
                        owner: nil,
                        imageURL: nil
                    )
                }
            }
        }
        
        // Handle https://open.spotify.com URLs
        if let url = URL(string: urlString),
           url.host?.contains("spotify.com") == true || url.host?.contains("spotify.link") == true {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            
            if pathComponents.count >= 2 {
                let type = pathComponents[0] // track or playlist
                let id = pathComponents[1]
                if type == "track" || type == "playlist" {
                    let finalURL = urlString.hasPrefix("https://") ? urlString : "https://open.spotify.com/\(type)/\(id)"
                    return SpotifyLink(
                        id: id,
                        url: finalURL,
                        type: type,
                        name: type == "track" ? "Track" : "Playlist",
                        artist: nil,
                        owner: nil,
                        imageURL: nil
                    )
                }
            }
        }
        
        return nil
    }
    
    private func parseAppleMusicURL(_ urlString: String) -> SpotifyLink? {
        let urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Apple Music URL formats:
        // https://music.apple.com/us/album/song-name/1234567890?i=9876543210
        // https://music.apple.com/us/playlist/playlist-name/pl.u-...
        // https://music.apple.com/album/id1234567890
        
        guard let url = URL(string: urlString),
              url.host?.contains("music.apple.com") == true else {
            return nil
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        // Check for album/track
        if pathComponents.contains("album") {
            // Extract album ID from path or query
            var albumId: String?
            var trackId: String?
            
            // Try to get ID from path (format: /album/id1234567890)
            if let idIndex = pathComponents.firstIndex(where: { $0.hasPrefix("id") }) {
                albumId = String(pathComponents[idIndex].dropFirst(2)) // Remove "id" prefix
            } else if pathComponents.count >= 2 {
                // Try to get from path components
                albumId = pathComponents.last
            }
            
            // Check for track ID in query parameters (i=...)
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let iParam = queryItems.first(where: { $0.name == "i" })?.value {
                trackId = iParam
            }
            
            if let albumId = albumId {
                let type = trackId != nil ? "track" : "album"
                let id = trackId ?? albumId
                return SpotifyLink(
                    id: id,
                    url: urlString,
                    type: type,
                    name: type == "track" ? "Track" : "Album",
                    artist: nil,
                    owner: nil,
                    imageURL: nil
                )
            }
        }
        
        // Check for playlist
        if pathComponents.contains("playlist") {
            // Extract playlist ID
            var playlistId: String?
            
            // Playlist format: /playlist/pl.u-...
            if let plIndex = pathComponents.firstIndex(where: { $0.hasPrefix("pl.") }) {
                playlistId = pathComponents[plIndex]
            } else if pathComponents.count >= 2 {
                playlistId = pathComponents.last
            }
            
            if let playlistId = playlistId {
                return SpotifyLink(
                    id: playlistId,
                    url: urlString,
                    type: "playlist",
                    name: "Playlist",
                    artist: nil,
                    owner: nil,
                    imageURL: nil
                )
            }
        }
        
        return nil
    }
}

