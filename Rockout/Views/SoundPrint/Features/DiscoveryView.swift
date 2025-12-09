import SwiftUI

struct DiscoveryView: View {
    let discoverWeekly: DiscoverWeekly?
    let releaseRadar: ReleaseRadar?
    let recentlyDiscovered: [RecentlyDiscovered]
    let realYouMix: RealYouMix?
    let soundprintForecast: SoundprintForecast?
    let discoveryBundle: DiscoveryBundle?
    let onOpenInSpotify: (String, [UnifiedTrack]) -> Void
    let onOpenPlaylist: (String) -> Void
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // The Real You Mix
                if let mix = realYouMix, !mix.tracks.isEmpty {
                    PlaylistCard(
                        title: mix.title,
                        description: mix.description,
                        tracks: mix.tracks,
                        onOpenInSpotify: { onOpenInSpotify(mix.title, mix.tracks) }
                    )
                }
                
                // Soundprint Forecast
                if let forecast = soundprintForecast, !forecast.suggestedTracks.isEmpty {
                    PlaylistCard(
                        title: "Soundprint Forecast",
                        description: forecast.headline,
                        tracks: forecast.suggestedTracks,
                        onOpenInSpotify: { onOpenInSpotify("Soundprint Forecast", forecast.suggestedTracks) }
                    )
                }
                
                // Discovery Bundle
                if let bundle = discoveryBundle {
                    if !bundle.newTracks.isEmpty {
                        PlaylistCard(
                            title: "Discovery Bundle",
                            description: "\(bundle.newTracks.count) new tracks, \(bundle.newArtists.count) new artists, \(bundle.newGenres.count) new genres",
                            tracks: bundle.newTracks,
                            onOpenInSpotify: { onOpenInSpotify("Discovery Bundle", bundle.newTracks) }
                        )
                    } else {
                        // Show empty state for Discovery Bundle
                        EmptyPlaylistCard(
                            title: "Discovery Bundle",
                            description: "No new discoveries yet. Keep listening to discover new music!"
                        )
                    }
                }
                
                // Discover Weekly
                if let weekly = discoverWeekly {
                    if !weekly.tracks.isEmpty {
                        if let playlistId = weekly.playlistId {
                            // Open existing Spotify playlist
                            NativePlaylistCard(
                                title: "Discover Weekly",
                                description: "Your personalized weekly mix",
                                tracks: weekly.tracks,
                                onOpenPlaylist: { onOpenPlaylist(playlistId) }
                            )
                        } else {
                            // Create new playlist if ID not found
                            PlaylistCard(
                                title: "Discover Weekly",
                                description: "Your personalized weekly mix",
                                tracks: weekly.tracks,
                                onOpenInSpotify: { onOpenInSpotify("Discover Weekly", weekly.tracks) }
                            )
                        }
                    } else {
                        EmptyPlaylistCard(
                            title: "Discover Weekly",
                            description: "Your weekly mix will appear here once available"
                        )
                    }
                }
                
                // Release Radar
                if let radar = releaseRadar {
                    if !radar.tracks.isEmpty {
                        if let playlistId = radar.playlistId {
                            // Open existing Spotify playlist
                            NativePlaylistCard(
                                title: "Release Radar",
                                description: "New releases from artists you follow",
                                tracks: radar.tracks,
                                onOpenPlaylist: { onOpenPlaylist(playlistId) }
                            )
                        } else {
                            // Create new playlist if ID not found
                            PlaylistCard(
                                title: "Release Radar",
                                description: "New releases from artists you follow",
                                tracks: radar.tracks,
                                onOpenInSpotify: { onOpenInSpotify("Release Radar", radar.tracks) }
                            )
                        }
                    } else {
                        EmptyPlaylistCard(
                            title: "Release Radar",
                            description: "New releases will appear here when available"
                        )
                    }
                }
                
                // Recently Discovered Artists
                if !recentlyDiscovered.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recently Discovered")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        ForEach(recentlyDiscovered.prefix(10), id: \.artist.id) { discovery in
                            RecentlyDiscoveredRow(discovery: discovery)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

struct PlaylistCard: View {
    let title: String
    let description: String
    let tracks: [UnifiedTrack]
    let onOpenInSpotify: () -> Void
    
    @State private var isOpening = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(tracks.count) tracks")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
            }
            
            // Open in Spotify button
            Button {
                isOpening = true
                Task {
                    onOpenInSpotify()
                    // Reset after a short delay to allow Spotify to open
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        isOpening = false
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isOpening {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("Open in Spotify")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green)
                .cornerRadius(20)
            }
            .disabled(isOpening)
            
            // Preview tracks
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tracks.prefix(5), id: \.id) { track in
                        TrackPreviewCard(track: track)
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
}

struct TrackPreviewCard: View {
    let track: UnifiedTrack
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageURL = track.album?.imageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 80, height: 80)
                .cornerRadius(8)
            }
            
            Text(track.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .lineLimit(2)
                .frame(width: 80)
        }
    }
}

struct RecentlyDiscoveredRow: View {
    let discovery: RecentlyDiscovered
    
    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = discovery.artist.imageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(discovery.artist.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Discovered \(formatDate(discovery.discoveredDate))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Text("\(discovery.playCount) plays")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct NativePlaylistCard: View {
    let title: String
    let description: String
    let tracks: [UnifiedTrack]
    let onOpenPlaylist: () -> Void
    
    @State private var isOpening = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(tracks.count) tracks")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
            }
            
            // Open in Spotify button
            Button {
                isOpening = true
                Task {
                    onOpenPlaylist()
                    // Reset after a short delay to allow Spotify to open
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        isOpening = false
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if isOpening {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("Open in Spotify")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green)
                .cornerRadius(20)
            }
            .disabled(isOpening)
            
            // Preview tracks
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tracks.prefix(5), id: \.id) { track in
                        TrackPreviewCard(track: track)
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
}

struct EmptyPlaylistCard: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text(description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
        )
    }
}

