import SwiftUI
import AVKit
import UIKit

struct FullScreenMediaView: View {
    let imageURLs: [URL]
    let videoURL: URL?
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dismissOffset: CGFloat = 0
    @State private var player: AVPlayer?
    @State private var isMuted: Bool = true
    
    init(imageURLs: [URL] = [], videoURL: URL? = nil, initialIndex: Int = 0) {
        self.imageURLs = imageURLs
        self.videoURL = videoURL
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let videoURL = videoURL {
                // Video player with built-in controls
                videoPlayerView(videoURL: videoURL)
            } else if !imageURLs.isEmpty {
                // Image carousel
                imageCarouselView
            }
            
            // Close button (only show for images, video player has its own controls)
            if videoURL == nil {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        .offset(y: dismissOffset)
        .gesture(
            // Only allow vertical swipe-to-dismiss when not zoomed
            scale <= 1.0 ?
            DragGesture()
                .onChanged { value in
                    // Only track vertical drag
                    if abs(value.translation.height) > abs(value.translation.width) {
                        dismissOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    // Dismiss if dragged up or down more than 100 points
                    if abs(value.translation.height) > 100 {
                        dismiss()
                    } else {
                        // Spring back to original position
                        withAnimation(.spring()) {
                            dismissOffset = 0
                        }
                    }
                }
            : nil
        )
        .onAppear {
            // Initialize player when view appears if we have a video
            if let videoURL = videoURL, player == nil {
                player = AVPlayer(url: videoURL)
                player?.isMuted = true
            }
        }
    }
    
    private var imageCarouselView: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(imageURLs.enumerated()), id: \.offset) { index, url in
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastScale * value
                                        // Constrain zoom between 1.0 and 4.0
                                        scale = min(max(newScale, 1.0), 4.0)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        // If zoomed back to 1.0, reset offset
                                        if scale <= 1.0 {
                                            withAnimation {
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                scale > 1.0 ? 
                                AnyGesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let newOffset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                        offset = newOffset
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }) : AnyGesture(DragGesture(minimumDistance: CGFloat.infinity)
                                    .onChanged { _ in }
                                    .onEnded { _ in })
                            )
                            .onTapGesture(count: 2) {
                                // Double tap to reset zoom
                                withAnimation {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                    case .failure:
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.5))
                            Text("Failed to load image")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .onChange(of: currentIndex) { _, _ in
            // Reset zoom and position when switching images
            withAnimation {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            }
        }
    }
    
    private func videoPlayerView(videoURL: URL) -> some View {
        Group {
            if let player = player {
                FullScreenVideoPlayer(player: player, isMuted: $isMuted)
                .ignoresSafeArea(.all)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            if player == nil {
                player = AVPlayer(url: videoURL)
                player?.isMuted = isMuted
                // Start playing immediately
                DispatchQueue.main.async {
                    player?.play()
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - Full Screen Video Player Controller

struct FullScreenVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    @Binding var isMuted: Bool
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true // Built-in play/pause/scrub/fullscreen/close controls
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = false
        
        // Note: AVPlayerViewController has built-in close button (X) in its controls
        // The dismiss is handled automatically by SwiftUI when presented as fullScreenCover
        // No custom close button needed
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player?.isMuted = isMuted
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
    }
}
