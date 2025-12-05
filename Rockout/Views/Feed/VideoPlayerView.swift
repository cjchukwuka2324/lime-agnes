import SwiftUI
import AVKit
import UIKit

struct VideoPlayerView: View {
    let videoURL: URL
    @State private var player: AVPlayer?
    @State private var isMuted: Bool = true
    
    init(videoURL: URL) {
        self.videoURL = videoURL
    }
    
    var body: some View {
        ZStack {
            if let player = player {
                CompactVideoPlayer(player: player, isMuted: $isMuted)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxHeight: 450)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fill)
                    .frame(maxHeight: 450)
                    .overlay(
                        ProgressView()
                            .tint(.white)
                    )
            }
        }
        .onAppear {
            if player == nil {
                player = AVPlayer(url: videoURL)
                player?.isMuted = isMuted
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - Compact Video Player for Feed Cards

struct CompactVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var isMuted: Bool
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true // Built-in play/pause/scrub/fullscreen controls
        controller.videoGravity = .resizeAspectFill
        controller.allowsPictureInPicturePlayback = false
        
        // Add mute button overlay (not built into AVPlayerViewController)
        let muteButton = UIButton(type: .system)
        muteButton.setImage(UIImage(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"), for: .normal)
        muteButton.tintColor = .white
        muteButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        muteButton.layer.cornerRadius = 20
        muteButton.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        muteButton.addTarget(context.coordinator, action: #selector(Coordinator.muteButtonTapped), for: .touchUpInside)
        
        controller.view.addSubview(muteButton)
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            muteButton.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            muteButton.trailingAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            muteButton.widthAnchor.constraint(equalToConstant: 40),
            muteButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Note: Fullscreen and close buttons are built into AVPlayerViewController controls
        // No custom buttons needed - iOS handles these automatically
        
        context.coordinator.muteButton = muteButton
        context.coordinator.isMutedBinding = $isMuted
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player?.isMuted = isMuted
        context.coordinator.isMutedBinding = $isMuted
        // Update mute button icon
        let iconName = isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        context.coordinator.muteButton?.setImage(UIImage(systemName: iconName), for: .normal)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var muteButton: UIButton?
        var isMutedBinding: Binding<Bool>?
        
        @objc func muteButtonTapped() {
            if var binding = isMutedBinding {
                binding.wrappedValue.toggle()
            }
        }
    }
}
