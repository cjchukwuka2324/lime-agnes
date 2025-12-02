import SwiftUI

struct SpotifyLinkCardView: View {
    let spotifyLink: SpotifyLink
    
    var body: some View {
        Button {
            openInSpotify()
        } label: {
            HStack(spacing: 12) {
                // Album/Playlist Artwork
                Group {
                    if let imageURL = spotifyLink.imageURL {
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
                    } else {
                        defaultArtwork
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Track/Playlist Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(spotifyLink.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if spotifyLink.type == "track", let artist = spotifyLink.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    } else if spotifyLink.type == "playlist", let owner = spotifyLink.owner {
                        Text("Playlist • \(owner)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Play Button
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(hex: "#1ED760"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
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
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.6))
            )
    }
    
    private func openInSpotify() {
        // Open Spotify URL in Spotify app or web
        // Try Spotify app first, then fall back to web
        let spotifyURL = spotifyLink.url
        
        // Check if we can open in Spotify app
        if let spotifyAppURL = URL(string: spotifyURL.replacingOccurrences(of: "https://open.spotify.com/", with: "spotify:")) {
            if UIApplication.shared.canOpenURL(spotifyAppURL) {
                UIApplication.shared.open(spotifyAppURL)
                return
            }
        }
        
        // Fall back to web URL
        if let url = URL(string: spotifyURL) {
            UIApplication.shared.open(url)
        }
    }
}
