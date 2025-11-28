import SwiftUI

struct MainTabView: View {
    @StateObject private var spotifyAuth = SpotifyAuthService.shared
    @EnvironmentObject var shareHandler: SharedAlbumHandler
    @State private var selectedTab = 0
    @State private var edgeDragStart: CGFloat?
    
    var body: some View {
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
                    Label("StudioSessions", systemImage: "mic.and.signal.meter.fill")
                }
                .tag(2)

            ProfileView()
                .environmentObject(spotifyAuth)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(3)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    // Only track if starting from screen edge (first touch)
                    if edgeDragStart == nil {
                        let startX = value.startLocation.x
                        let screenWidth = UIScreen.main.bounds.width
                        let edgeThreshold: CGFloat = 25 // Only from very edges
                        
                        // Check if drag started from left or right edge
                        if startX < edgeThreshold || startX > screenWidth - edgeThreshold {
                            edgeDragStart = startX
                        }
                    }
                }
                .onEnded { value in
                    defer { edgeDragStart = nil }
                    
                    // Only handle if drag started from edge
                    guard let startX = edgeDragStart else { return }
                    
                    let screenWidth = UIScreen.main.bounds.width
                    let edgeThreshold: CGFloat = 25
                    let isLeftEdge = startX < edgeThreshold
                    let isRightEdge = startX > screenWidth - edgeThreshold
                    
                    guard isLeftEdge || isRightEdge else { return }
                    
                    let horizontalAmount = value.translation.width
                    let verticalAmount = abs(value.translation.height)
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    
                    // Only handle clearly horizontal swipes from edges
                    // Require swipe to be at least 5x more horizontal than vertical (very strict)
                    guard abs(horizontalAmount) > verticalAmount * 5 else { return }
                    
                    let distanceThreshold: CGFloat = 180 // Higher threshold - very deliberate swipe needed
                    let velocityThreshold: CGFloat = 800 // Higher velocity threshold
                    
                    let shouldSwipeRight = horizontalAmount > distanceThreshold || velocity > velocityThreshold
                    let shouldSwipeLeft = horizontalAmount < -distanceThreshold || velocity < -velocityThreshold
                    
                    if shouldSwipeRight && selectedTab > 0 {
                        // Swipe right - go to previous tab
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab -= 1
                        }
                    } else if shouldSwipeLeft && selectedTab < 3 {
                        // Swipe left - go to next tab
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
    }
}
