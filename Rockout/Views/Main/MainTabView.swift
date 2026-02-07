import SwiftUI
import UIKit

struct MainTabView: View {
    @StateObject private var spotifyAuth = SpotifyAuthService.shared
    @EnvironmentObject var shareHandler: SharedAlbumHandler
    @StateObject private var playerVM = AudioPlayerViewModel.shared
    @State private var selectedTab = 0
    // Note: SpotifyAuthService kept for Profile tab which still uses it
    @State private var edgeDragStart: CGFloat?
    @State private var showAcceptShareSheet = false
    @State private var shareTokenToAccept: String?

    var body: some View {
        ZStack(alignment: .bottom) {

            // MARK: - MAIN TABVIEW
            // Note: SoundPrint and RockList features exist in the codebase but are intentionally
            // hidden from the tab bar for the current MVP. They can be activated in the future by
            // uncommenting their tab entries below.
            //
            // Available but hidden features:
            // - SoundPrint: Music analytics dashboard (Views/SoundPrint/)
            // - RockList: Competitive leaderboards (Views/RockList/, Models/RockList/, Services/RockList/, ViewModels/RockList/)
            TabView(selection: $selectedTab) {

                FeedView()
                    .tabItem {
                        Label("GreenRoom", systemImage: "house.fill")
                    }
                    .tag(0)

                RecallHomeView()
                    .tabItem {
                        Label("Recall", systemImage: "sparkles.magnifyingglass")
                    }
                    .tag(1)
                    .onAppear {
                        setupRecallTabBarIcon()
                    }
                    .onChange(of: selectedTab) { oldValue, newValue in
                        // Ensure icon is set when tab is selected
                        if newValue == 1 {
                            setupRecallTabBarIcon()
                        }
                    }

                StudioSessionsView()
                    .environmentObject(shareHandler)
                    .tabItem {
                        Label("StudioSessions", systemImage: "slider.horizontal.3")
                    }
                    .tag(2)

                ProfileView()
                    .environmentObject(spotifyAuth)
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    .tag(3)
                
                // MARK: - HIDDEN FEATURES (Available for future MVP phases)
                // Uncomment below to enable SoundPrint tab:
                /*
                SoundPrintView()
                    .environmentObject(spotifyAuth)
                    .tabItem {
                        Label("SoundPrint", systemImage: "waveform.circle.fill")
                    }
                    .tag(4)
                */
                
                // Uncomment below to enable RockList tab:
                /*
                RockListView()
                    .tabItem {
                        Label("RockList", systemImage: "chart.bar.fill")
                    }
                    .tag(5)
                */
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if edgeDragStart == nil {
                            let startX = value.startLocation.x
                            let screenWidth = UIScreen.main.bounds.width
                            let edgeThreshold: CGFloat = 25

                            if startX < edgeThreshold || startX > screenWidth - edgeThreshold {
                                edgeDragStart = startX
                            }
                        }
                    }
                    .onEnded { value in
                        defer { edgeDragStart = nil }
                        guard let startX = edgeDragStart else { return }

                        let screenWidth = UIScreen.main.bounds.width
                        let edgeThreshold: CGFloat = 25
                        let isLeftEdge = startX < edgeThreshold
                        let isRightEdge = startX > screenWidth - edgeThreshold
                        guard isLeftEdge || isRightEdge else { return }

                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        let velocity = value.predictedEndTranslation.width - value.translation.width

                        guard abs(horizontalAmount) > verticalAmount * 5 else { return }

                        let distanceThreshold: CGFloat = 180
                        let velocityThreshold: CGFloat = 800

                        let shouldSwipeRight = horizontalAmount > distanceThreshold || velocity > velocityThreshold
                        let shouldSwipeLeft = horizontalAmount < -distanceThreshold || velocity < -velocityThreshold

                        if shouldSwipeRight && selectedTab > 0 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab -= 1
                            }
                        } else if shouldSwipeLeft && selectedTab < 3 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab += 1
                            }
                        }
                        // Note: Max tab is still 3 (Profile), but SoundPrint removed
                    }
            )
            .onReceive(NotificationCenter.default.publisher(for: .navigateToFeed)) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = 0
                }
            }

            // MARK: - BOTTOM MINI PLAYER
            if playerVM.currentTrack != nil {
                BottomPlayerBar(playerVM: playerVM)
                    .background(Color.black)
                    .padding(.bottom, 50) // Constant padding above tab bar
                    .transition(.move(edge: .bottom))
            }

        }
        .onChange(of: shareHandler.shouldShowAcceptSheet) { _, shouldShow in
            if shouldShow, let token = shareHandler.pendingShareToken {
                shareTokenToAccept = token
                showAcceptShareSheet = true
                shareHandler.shouldShowAcceptSheet = false
            }
        }
        .sheet(isPresented: $showAcceptShareSheet) {
            if let token = shareTokenToAccept {
                AcceptSharedAlbumView(
                    shareToken: token,
                    onAccept: { isCollaboration in
                        // Navigate to Studio Sessions tab first
                        withAnimation {
                            selectedTab = 2 // Studio Sessions tab
                        }
                        // Notify StudioSessionsView to reload and navigate to correct subtab
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            NotificationCenter.default.post(
                                name: NSNotification.Name("AcceptSharedAlbum"),
                                object: nil,
                                userInfo: ["isCollaboration": isCollaboration]
                            )
                        }
                    },
                    onOwnerDetected: {
                        // Navigate to Studio Sessions tab (My Albums)
                        withAnimation {
                            selectedTab = 2 // Studio Sessions tab
                        }
                        // Notify StudioSessionsView to navigate to My Albums
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            NotificationCenter.default.post(
                                name: NSNotification.Name("NavigateToMyAlbums"),
                                object: nil
                            )
                        }
                    }
                )
            }
        }
    }
    
    // MARK: - Recall Tab Bar Icon Setup
    
    private func setupRecallTabBarIcon() {
        // Try multiple times to ensure icon is set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setRecallIcon()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.setRecallIcon()
        }
    }
    
    private func setRecallIcon() {
            // Find the tab bar controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                return
            }
            
            // Traverse view hierarchy to find UITabBarController
            func findTabBarController(in viewController: UIViewController?) -> UITabBarController? {
                guard let vc = viewController else { return nil }
                if let tabBar = vc as? UITabBarController {
                    return tabBar
                }
                for child in vc.children {
                    if let tabBar = findTabBarController(in: child) {
                        return tabBar
                    }
                }
                return nil
            }
            
            guard let tabBarController = findTabBarController(in: window.rootViewController) else {
                // Fallback: Use system icon if tab bar controller not found
                return
            }
            
            // Get the Recall tab (index 1)
            guard tabBarController.tabBar.items?.count ?? 0 > 1,
                  let recallTabItem = tabBarController.tabBar.items?[1] else {
                // Fallback: Use system icon if tab item not found
                return
            }
            
            // Create pulsing orb icon using UIKit layers
            let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
            containerView.backgroundColor = .clear
            
            // Create pulsing orb layer
            let orbLayer = CAShapeLayer()
            orbLayer.frame = CGRect(x: 7, y: 7, width: 16, height: 16)
            orbLayer.path = UIBezierPath(ovalIn: orbLayer.bounds).cgPath
            let spotifyGreen = Color(hex: "#1ED760")
            orbLayer.fillColor = UIColor(spotifyGreen).cgColor
            
            // Add glow
            orbLayer.shadowColor = UIColor(spotifyGreen).cgColor
            orbLayer.shadowRadius = 4
            orbLayer.shadowOpacity = 0.6
            orbLayer.shadowOffset = .zero
            
            containerView.layer.addSublayer(orbLayer)
            
            // Add pulsing animation
            let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
            pulseAnimation.fromValue = 1.0
            pulseAnimation.toValue = 1.2
            pulseAnimation.duration = 1.5
            pulseAnimation.autoreverses = true
            pulseAnimation.repeatCount = .infinity
            pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            orbLayer.add(pulseAnimation, forKey: "pulse")
            
            // Add sparkles
            for i in 0..<3 {
                let sparkle = CAShapeLayer()
                sparkle.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
                sparkle.path = UIBezierPath(ovalIn: sparkle.bounds).cgPath
                sparkle.fillColor = UIColor.white.cgColor
                sparkle.opacity = 0.6
                
                let angle = CGFloat(i) * 2 * .pi / 3
                sparkle.position = CGPoint(
                    x: 15 + cos(angle) * 10,
                    y: 15 + sin(angle) * 10
                )
                
                containerView.layer.addSublayer(sparkle)
                
                // Animate sparkles
                let sparkleAnimation = CABasicAnimation(keyPath: "opacity")
                sparkleAnimation.fromValue = 0.3
                sparkleAnimation.toValue = 0.8
                sparkleAnimation.duration = 1.5
                sparkleAnimation.beginTime = CACurrentMediaTime() + Double(i) * 0.5
                sparkleAnimation.autoreverses = true
                sparkleAnimation.repeatCount = .infinity
                sparkleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                sparkle.add(sparkleAnimation, forKey: "sparkle")
            }
            
            // Render to image (static snapshot for tab bar)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30))
            let iconImage = renderer.image { context in
                containerView.layer.render(in: context.cgContext)
            }
            
            // Set the icon
            recallTabItem.image = iconImage.withRenderingMode(.alwaysOriginal)
            recallTabItem.selectedImage = iconImage.withRenderingMode(.alwaysOriginal)
    }
}

// UIColor hex initializer is now in Extensions/UIColor+Hex.swift
