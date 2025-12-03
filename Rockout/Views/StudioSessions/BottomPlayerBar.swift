import SwiftUI

struct BottomPlayerBar: View {
    @ObservedObject var playerVM: AudioPlayerViewModel
    
    @State private var showFullPlayer = false
    
    var body: some View {
        if let track = playerVM.currentTrack {
            Button {
                showFullPlayer = true
            } label: {
                HStack(spacing: 12) {
                    // Album Cover Art
                    Group {
                        if let album = playerVM.currentAlbum,
                           let urlString = album.cover_art_url,
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
                    .frame(width: 50, height: 50)
                    .cornerRadius(8)
                    
                    // Track Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let album = playerVM.currentAlbum {
                            Text(album.title)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Playback Controls
                    HStack(spacing: 16) {
                        // Rewind 15s
                        Button {
                            playerVM.seek(to: max(0, playerVM.currentTime - 15))
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                        
                        // Play/Pause
                        Button {
                            if playerVM.isPlaying {
                                playerVM.pause()
                            } else {
                                playerVM.play()
                            }
                        } label: {
                            Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        // Forward 15s
                        Button {
                            playerVM.seek(to: min(playerVM.duration, playerVM.currentTime + 15))
                        } label: {
                            Image(systemName: "goforward.15")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.9))
                .overlay(
                    // Progress indicator at the top
                    GeometryReader { geometry in
                        if playerVM.duration > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 2)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: geometry.size.width * CGFloat(playerVM.currentTime / playerVM.duration))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                )
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                )
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showFullPlayer) {
                if let track = playerVM.currentTrack {
                    AudioPlayerView(track: track)
                }
            }
        }
    }
    
    private var albumPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

