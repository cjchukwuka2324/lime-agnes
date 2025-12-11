import SwiftUI
import UIKit

struct MainTabView: View {
    @StateObject private var spotifyAuth = SpotifyAuthService.shared
    @EnvironmentObject var shareHandler: SharedAlbumHandler
    @StateObject private var playerVM = AudioPlayerViewModel.shared
    @StateObject private var tabBarState = TabBarState.shared
    @State private var selectedTab = 0
    @State private var edgeDragStart: CGFloat?
    @State private var showAcceptShareSheet = false
    @State private var shareTokenToAccept: String?

    var body: some View {

        ZStack(alignment: .bottom) {

            // MARK: - MAIN TABVIEW
            TabView(selection: $selectedTab) {

                FeedView()
                    .tabItem {
                        Label("GreenRoom", systemImage: "house.fill")
                    }
                    .tag(0)

                SoundPrintView()
                    .environmentObject(spotifyAuth)
                    .tabItem {
                        Label("SoundPrint", systemImage: "waveform")
                    }
                    .tag(1)

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
            }
            .background(Color.black)
            .background(TabBarUpdater(tabBarState: tabBarState))
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged(onDragChanged)
                    .onEnded(onDragEnded)
            )
            .onReceive(NotificationCenter.default.publisher(for: .navigateToFeed)) { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    selectedTab = 0
                }
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                // If tab bar is collapsed and user taps a tab, expand it
                if tabBarState.isCollapsed && oldValue != newValue {
                    tabBarState.expand()
                }
            }
            .onTapGesture {
                // If tab bar is collapsed and user taps anywhere on the tab view, expand it
                if tabBarState.isCollapsed {
                    tabBarState.expand()
                }
            }

            // ⭐ MINI PLAYER (ALWAYS ABOVE TAB BAR)
            if playerVM.currentTrack != nil {
                BottomPlayerBar(playerVM: playerVM)
                    .transition(.move(edge: .bottom))
                    .offset(y: tabBarState.isCollapsed ? -49 : 0) // Move down to tab bar level when collapsed
                    .padding(.bottom, 50) // Constant padding above tab bar
            }
        }

        .background(Color.black.ignoresSafeArea())

        // YOUR EXISTING SHEETS / LOGIC UNCHANGED
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
                    onAccept: handleAcceptCollaboration,
                    onOwnerDetected: handleOwnerDetected
                )
            }
        }
    }

    // MARK: - Drag gesture methods (UNCHANGED)
    private func onDragChanged(_ value: DragGesture.Value) {
        if edgeDragStart == nil {
            let startX = value.startLocation.x
            let screenWidth = UIScreen.main.bounds.width
            let edgeThreshold: CGFloat = 25

            if startX < edgeThreshold || startX > screenWidth - edgeThreshold {
                edgeDragStart = startX
            }
        }
    }

    private func onDragEnded(_ value: DragGesture.Value) {
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
    }

    private func handleAcceptCollaboration(isCollaboration: Bool) {
        withAnimation {
            selectedTab = 2
        }
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            NotificationCenter.default.post(
                name: NSNotification.Name("AcceptSharedAlbum"),
                object: nil,
                userInfo: ["isCollaboration": isCollaboration]
            )
        }
    }

    private func handleOwnerDetected() {
        withAnimation {
            selectedTab = 2
        }
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            NotificationCenter.default.post(
                name: NSNotification.Name("NavigateToMyAlbums"),
                object: nil
            )
        }
    }
    
    // MARK: - Tab Bar Appearance
    
    private func updateTabBarAppearance(collapsed: Bool) {
        DispatchQueue.main.async {
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithOpaqueBackground()
            tabBarAppearance.backgroundColor = UIColor.black
            tabBarAppearance.shadowColor = .clear
            tabBarAppearance.backgroundEffect = nil
            
            if collapsed {
                // Collapsed: hide labels by making them transparent and moving them
                tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: UIColor.clear,
                    .font: UIFont.systemFont(ofSize: 0)
                ]
                tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: UIColor.clear,
                    .font: UIFont.systemFont(ofSize: 0)
                ]
                tabBarAppearance.stackedLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 100)
                tabBarAppearance.stackedLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 100)
            } else {
                // Expanded: show labels
                tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.6)]
                tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
                tabBarAppearance.stackedLayoutAppearance.normal.titlePositionAdjustment = .zero
                tabBarAppearance.stackedLayoutAppearance.selected.titlePositionAdjustment = .zero
            }
            
            tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
            tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
            
            UITabBar.appearance().standardAppearance = tabBarAppearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            }
            
            // Force update all tab bars
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.subviews.forEach { view in
                    if let tabBar = view as? UITabBar {
                        tabBar.setNeedsLayout()
                        tabBar.layoutIfNeeded()
                    }
                }
            }
        }
    }
}
