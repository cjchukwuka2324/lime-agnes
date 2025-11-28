import SwiftUI

struct MainTabView: View {
    @StateObject private var spotifyAuth = SpotifyAuthService.shared
    @EnvironmentObject var shareHandler: SharedAlbumHandler
    @State private var selectedTab = 0
    
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
        .onReceive(NotificationCenter.default.publisher(for: .navigateToFeed)) { _ in
            selectedTab = 0
        }
    }
}
