import SwiftUI
import AVKit

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
                // Video player
                videoPlayerView(videoURL: videoURL)
            } else if !imageURLs.isEmpty {
                // Image carousel
                imageCarouselView
            }
            
            // Close button
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
                                SimultaneousGesture(
                                    // Zoom gesture
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
                                        },
                                    // Pan gesture - only allow when zoomed in
                                    DragGesture()
                                        .onChanged { value in
                                            // Only allow panning when zoomed (scale > 1.0)
                                            guard scale > 1.0 else { return }
                                            
                                            let newOffset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                            
                                            // Constrain panning to keep image within bounds
                                            // This is a simple constraint - you can make it more sophisticated
                                            offset = newOffset
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
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
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all)
                    .onAppear {
                        player.isMuted = isMuted
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                ProgressView()
                    .tint(.white)
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
