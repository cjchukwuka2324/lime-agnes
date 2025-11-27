import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
    
    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 300)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.7))
                            Text("Video")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    )
            }
        }
        .onAppear {
            player = AVPlayer(url: videoURL)
        }
    }
}


