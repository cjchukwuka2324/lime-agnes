import SwiftUI

struct BottomPlayerBar: View {
    @ObservedObject var playerVM: AudioPlayerViewModel
    @StateObject private var tabBarState = TabBarState.shared
    @State private var showFullPlayer = false
    
    var body: some View {
        if let track = playerVM.currentTrack {
            
            Button {
                showFullPlayer = true
            } label: {
                // MAIN BAR CONTENT
                HStack(spacing: 8) {
                    
                    // --- COVER ART ---
                    albumArt
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // --- TITLE & ARTIST ---
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let album = playerVM.currentAlbum,
                           let artistName = album.artist_name {
                            Text(artistName)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // --- PLAYBACK CONTROLS ---
                    HStack(spacing: 16) {
                        
                        // previous track
                        Button {
                            playerVM.previousTrack()
                        } label: {
                            Image(systemName: "backward.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 20))
                        }
                        
                        // play/pause
                        Button {
                            if playerVM.isPlaying {
                                playerVM.pause()
                            } else {
                                playerVM.play()
                            }
                        } label: {
                            Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 24, weight: .bold))
                        }
                        
                        // next track
                        Button {
                            playerVM.nextTrack()
                        } label: {
                            Image(systemName: "forward.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 20))
                        }
                        
                        // dismiss/close button
                        Button {
                            playerVM.dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassMorphism()
                .clipShape(RoundedCorner(radius: 12, corners: [.topLeft, .topRight]))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFullPlayer) {
                if let track = playerVM.currentTrack {
                    AudioPlayerView(track: track)
                }
            }
        }
    }
    
    
    // MARK: - Album Art Loader
    
    private var albumArt: some View {
        Group {
            if let album = playerVM.currentAlbum,
               let urlString = album.cover_art_url,
               let url = URL(string: urlString) {
                
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
    }
    
    
    // MARK: - Placeholder Artwork
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.3))
            
            Image(systemName: "music.note")
                .foregroundColor(.white.opacity(0.3))
                .font(.system(size: 20))
        }
    }
}

// Extension to support corner radius on specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
