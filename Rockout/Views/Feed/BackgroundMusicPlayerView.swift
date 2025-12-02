import SwiftUI
import AVFoundation

struct BackgroundMusicPlayerView: View {
    let backgroundMusic: BackgroundMusic
    
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var hasStarted = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Track Artwork
            Group {
                if let imageURL = backgroundMusic.imageURL {
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
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Track Info
            VStack(alignment: .leading, spacing: 2) {
                Text(backgroundMusic.name)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(backgroundMusic.artist)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 8) {
                if backgroundMusic.previewURL != nil {
                    Button {
                        toggleMute()
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    if isPlaying {
                        Button {
                            stop()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                } else {
                    Text("No preview")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .onAppear {
            if !hasStarted {
                start()
            }
        }
        .onDisappear {
            stop()
        }
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
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            )
    }
    
    private func start() {
        guard let previewURL = backgroundMusic.previewURL else { return }
        
        hasStarted = true
        player = AVPlayer(url: previewURL)
        player?.volume = isMuted ? 0.0 : 1.0
        
        // Auto-play
        player?.play()
        isPlaying = true
        
        // Loop the preview (30 seconds)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
    
    private func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        hasStarted = false
    }
    
    private func toggleMute() {
        isMuted.toggle()
        player?.volume = isMuted ? 0.0 : 1.0
    }
}
