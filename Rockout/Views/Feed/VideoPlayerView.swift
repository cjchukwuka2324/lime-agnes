import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
    @State private var isMuted: Bool = true
    @State private var isPlaying: Bool = false
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxHeight: 1000)
                    .clipped()
                    .onAppear {
                        player.isMuted = isMuted
                        player.play()
                        isPlaying = true
                    }
                    .onDisappear {
                        player.pause()
                        isPlaying = false
                    }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxHeight: 1000)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
            
            // Mute/Unmute button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isMuted.toggle()
                        player?.isMuted = isMuted
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.5))
                            )
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear {
            player = AVPlayer(url: videoURL)
            player?.isMuted = true
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
