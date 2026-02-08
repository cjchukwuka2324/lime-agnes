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

            // MARK: - MAIN CONTENT VIEWS
            // Note: SoundPrint and RockList features exist in the codebase but are intentionally
            // hidden from the tab bar for the current MVP. They can be activated in the future by
            // adding additional cases to the tab selection.
            //
            // Available but hidden features:
            // - SoundPrint: Music analytics dashboard (Views/SoundPrint/)
            // - RockList: Competitive leaderboards (Views/RockList/, Models/RockList/, Services/RockList/, ViewModels/RockList/)
            
            ZStack {
                if selectedTab == 0 {
                    FeedView()
                }
                
                if selectedTab == 1 {
                    RecallHomeView()
                        .onAppear {
                            setupRecallTabBarIcon()
                        }
                }
                
                if selectedTab == 2 {
                    StudioSessionsView()
                        .environmentObject(shareHandler)
                }
                
                if selectedTab == 3 {
                    DiscoveriesView()
                        .environmentObject(shareHandler)
                }
                
                if selectedTab == 4 {
                    ProfileView()
                        .environmentObject(spotifyAuth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        } else if shouldSwipeLeft && selectedTab < 4 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab += 1
                            }
                        }
                        // Note: Max tab is now 4 (Profile)
                    }
            )
            .onReceive(NotificationCenter.default.publisher(for: .navigateToFeed)) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = 0
                }
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                // Ensure Recall icon is set when tab is selected
                if newValue == 1 {
                    setupRecallTabBarIcon()
                }
            }

            // MARK: - BOTTOM MINI PLAYER
            if playerVM.currentTrack != nil {
                BottomPlayerBar(playerVM: playerVM)
                    .padding(.bottom, 50) // Constant padding above tab bar
                    .transition(.move(edge: .bottom))
            }
            
            // MARK: - CUSTOM TAB BAR
            VStack(spacing: 0) {
                Spacer()
                CustomTabBar(selectedTab: $selectedTab)
                    .edgesIgnoringSafeArea(.bottom)
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
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else { return }
            
            func findTabBarController(in viewController: UIViewController?) -> UITabBarController? {
                guard let vc = viewController else { return nil }
                if let tabBar = vc as? UITabBarController { return tabBar }
                for child in vc.children {
                    if let tabBar = findTabBarController(in: child) { return tabBar }
                }
                return nil
            }
            
            guard let tabBarController = findTabBarController(in: window.rootViewController),
                  tabBarController.tabBar.items?.count ?? 0 > 1,
                  let recallTabItem = tabBarController.tabBar.items?[1] else { return }
            
            // Use Recall tab icon from asset (glowing orb image)
            let size = CGSize(width: 28, height: 28)
            guard let original = UIImage(named: "recall-tab-icon") else { return }
            let renderer = UIGraphicsImageRenderer(size: size)
            let iconImage = renderer.image { _ in
                original.draw(in: CGRect(origin: .zero, size: size))
            }
            recallTabItem.image = iconImage.withRenderingMode(.alwaysOriginal)
            recallTabItem.selectedImage = iconImage.withRenderingMode(.alwaysOriginal)
    }
}

// UIColor hex initializer is now in Extensions/UIColor+Hex.swift
