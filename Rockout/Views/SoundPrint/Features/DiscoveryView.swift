import SwiftUI

struct DiscoveryView: View {
    let discoverWeekly: DiscoverWeekly?
    let releaseRadar: ReleaseRadar?
    let recentlyDiscovered: [RecentlyDiscovered]
    let onAddToSpotify: (String, [SpotifyTrack]) -> Void
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Discover Weekly
                if let weekly = discoverWeekly, !weekly.tracks.isEmpty {
                    PlaylistCard(
                        title: "Discover Weekly",
                        description: "Your personalized weekly mix",
                        tracks: weekly.tracks,
                        onAddToSpotify: { onAddToSpotify("Discover Weekly", weekly.tracks) }
                    )
                }
                
                // Release Radar
                if let radar = releaseRadar, !radar.tracks.isEmpty {
                    PlaylistCard(
                        title: "Release Radar",
                        description: "New releases from artists you follow",
                        tracks: radar.tracks,
                        onAddToSpotify: { onAddToSpotify("Release Radar", radar.tracks) }
                    )
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
    let tracks: [SpotifyTrack]
    let onAddToSpotify: () -> Void
    
    @State private var isAdding = false
    
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
                
                Button {
                    isAdding = true
                    onAddToSpotify()
                } label: {
                    HStack(spacing: 8) {
                        if isAdding {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                            Text("Add to Spotify")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(20)
                }
                .disabled(isAdding)
            }
            
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
    let track: SpotifyTrack
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageURL = track.album?.images?.first?.url,
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
            if let imageURL = discovery.artist.images?.first?.url,
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

