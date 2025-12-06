import SwiftUI

struct MainTabView: View {
    @StateObject private var spotifyAuth = SpotifyAuthService.shared
    @EnvironmentObject var shareHandler: SharedAlbumHandler
    @StateObject private var playerVM = AudioPlayerViewModel.shared
    @State private var selectedTab = 0
    @State private var edgeDragStart: CGFloat?

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - MAIN TABVIEW
            TabView(selection: $selectedTab) {

                FeedView()
                    .tabItem {
                        Label("Feed", systemImage: "house.fill")
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
                        Label("StudioSessions", systemImage: "music.note.list")
                    }
                    .tag(2)

                ProfileView()
                    .environmentObject(spotifyAuth)
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                    .tag(3)
            }
            .ignoresSafeArea(.keyboard)
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
                    .transition(.move(edge: .bottom))
            }

        }
    }
}
