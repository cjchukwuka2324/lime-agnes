import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let videoURL: URL
    let onFullscreen: (() -> Void)?
    @State private var player: AVPlayer?
    @State private var isMuted: Bool = true
    @State private var isPlaying: Bool = false
    
    init(videoURL: URL, onFullscreen: (() -> Void)? = nil) {
        self.videoURL = videoURL
        self.onFullscreen = onFullscreen
    }
    
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
            
            // Control buttons overlay
            VStack {
                HStack {
                    Spacer()
                    // Mute/Unmute button
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
                
                // Bottom controls
                HStack {
                    Spacer()
                    // Fullscreen button
                    if let onFullscreen = onFullscreen {
                        Button {
                            onFullscreen()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
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
                }
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
