//
//  OnboardingVideoScreen.swift
//  Rockout
//
//  Video-based onboarding screen with looping video background, bottom mask for hiding
//  misspelled text, and SwiftUI text overlays.
//

import SwiftUI
import AVFoundation

struct OnboardingVideoScreen: View {
    let videoName: String
    let title: String
    let subtitle: String
    let description: String
    let bottomMaskFraction: CGFloat  // Fraction of screen height to mask (0.18-0.25 typical)
    let videoScale: CGFloat  // Scale factor for video (1.0 = normal, <1.0 = zoomed out)
    let contentBottomPadding: CGFloat  // Bottom padding for content overlay
    let onContinue: () -> Void
    let showSkip: Bool
    let onSkip: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video background - fills entire screen
                OnboardingVideoPlayerView(videoName: videoName, scale: videoScale)
                    .ignoresSafeArea(.all)
                
                // Light gradient overlay for text contrast
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // Bottom mask to hide misspelled video text
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.95),
                            Color.black
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * bottomMaskFraction)
                    .blur(radius: 8)
                }
                
                // Content overlay at bottom
                VStack {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        // Title - uppercase, neon green
                        Text(title)
                            .font(.system(size: 32, weight: .bold, design: .default))
                            .foregroundColor(Color.brandNeonGreen) // Neon green - matches welcome screen
                            .textCase(.uppercase)
                            .tracking(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        // Subtitle - white, semibold
                        Text(subtitle)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        
                        // Description - white, ~0.85 opacity
                        Text(description)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 30)
                            .padding(.top, 8)
                        
                        // Continue button - wide, neon green, pill shape
                        Button(action: onContinue) {
                            Text("Continue")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    Capsule()
                                        .fill(Color.brandNeonGreen) // Neon green - matches welcome screen
                                )
                                .padding(.horizontal, 40)
                                .padding(.top, 24)
                        }
                        
                        // Optional Skip button
                        if showSkip {
                            Button(action: onSkip) {
                                Text("Skip")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.top, 12)
                            }
                        }
                    }
                    .padding(.bottom, contentBottomPadding)
                }
            }
        }
    }
}

// MARK: - Video Player View

struct OnboardingVideoPlayerView: UIViewRepresentable {
    let videoName: String
    let scale: CGFloat  // Scale factor: 1.0 = normal, <1.0 = zoomed out (pan out)
    
    func makeUIView(context: Context) -> VideoPlayerContainerView {
        let view = VideoPlayerContainerView()
        view.backgroundColor = .black
        
        // Load video from bundle
        // Videos are in Rockout/Assets/OnboardingVideos/ but bundle structure may vary
        var url: URL?
        
        // Try different bundle loading methods
        // Method 1: Try with full path structure
        if let bundlePath = Bundle.main.resourcePath {
            let possiblePaths = [
                "\(bundlePath)/Rockout/Assets/OnboardingVideos/\(videoName).mp4",
                "\(bundlePath)/Assets/OnboardingVideos/\(videoName).mp4",
                "\(bundlePath)/OnboardingVideos/\(videoName).mp4",
                "\(bundlePath)/\(videoName).mp4"
            ]
            
            for pathString in possiblePaths {
                let pathURL = URL(fileURLWithPath: pathString)
                if FileManager.default.fileExists(atPath: pathURL.path) {
                    url = pathURL
                    print("✅ Found video at: \(pathURL.path)")
                    break
                }
            }
        }
        
        // Method 2: Try Bundle.main.url with subdirectory (if files are in bundle root)
        if url == nil {
            if let subdirURL = Bundle.main.url(forResource: videoName, withExtension: "mp4", subdirectory: "Rockout/Assets/OnboardingVideos") {
                url = subdirURL
                print("✅ Found video via subdirectory: Rockout/Assets/OnboardingVideos")
            } else if let subdirURL = Bundle.main.url(forResource: videoName, withExtension: "mp4", subdirectory: "Assets/OnboardingVideos") {
                url = subdirURL
                print("✅ Found video via subdirectory: Assets/OnboardingVideos")
            } else if let subdirURL = Bundle.main.url(forResource: videoName, withExtension: "mp4", subdirectory: "OnboardingVideos") {
                url = subdirURL
                print("✅ Found video via subdirectory: OnboardingVideos")
            } else if let directURL = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
                url = directURL
                print("✅ Found video at bundle root")
            }
        }
        
        guard let videoURL = url else {
            print("⚠️ Could not find video: \(videoName).mp4")
            print("   Bundle resource path: \(Bundle.main.resourcePath ?? "nil")")
            // Print available resources for debugging
            if let resourcePath = Bundle.main.resourcePath {
                print("   Available files in bundle root:")
                if let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
                    files.filter { $0.contains("onboarding") || $0.contains("mp4") }.forEach { print("     - \($0)") }
                }
            }
            return view
        }
        
        // Create player
        let player = AVPlayer(url: videoURL)
        player.actionAtItemEnd = .none // Prevent pause at end
        
        // Create player layer
        let playerLayer = AVPlayerLayer(player: player)
        // Always use resizeAspectFill to fill the screen
        playerLayer.videoGravity = .resizeAspectFill
        
        view.layer.addSublayer(playerLayer)
        view.playerLayer = playerLayer
        view.videoScale = scale
        
        // Set frame to fill the view
        playerLayer.frame = view.bounds
        
        // Store player in coordinator
        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer
        
        // Start playing
        player.play()
        
        // Set up looping
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        
        return view
    }
    
    func updateUIView(_ uiView: VideoPlayerContainerView, context: Context) {
        // Update scale if changed
        uiView.videoScale = scale
        // Frame will be updated automatically in layoutSubviews
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // Clean up
        coordinator.player?.pause()
        coordinator.player = nil
        coordinator.playerLayer = nil
        NotificationCenter.default.removeObserver(coordinator)
    }
}

// MARK: - Video Player Container View

class VideoPlayerContainerView: UIView {
    var playerLayer: AVPlayerLayer? {
        didSet {
            if let oldLayer = oldValue {
                oldLayer.removeFromSuperlayer()
            }
            if let newLayer = playerLayer {
                layer.addSublayer(newLayer)
            }
        }
    }
    
    var videoScale: CGFloat = 1.0 {
        didSet {
            updatePlayerLayerFrame()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updatePlayerLayerFrame()
    }
    
    private func updatePlayerLayerFrame() {
        guard let playerLayer = playerLayer else { return }
        // Always fill the screen
        playerLayer.frame = bounds
    }
}

// MARK: - Coordinator

class Coordinator: NSObject {
    var player: AVPlayer?
    var playerLayer: AVPlayerLayer?
    
    @objc func playerDidFinishPlaying() {
        // Loop video by seeking to start
        player?.seek(to: .zero)
        player?.play()
    }
}

