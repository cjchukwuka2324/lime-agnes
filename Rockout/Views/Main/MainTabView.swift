import SwiftUI

struct MainTabView: View {
    @StateObject private var spotifyAuth = SpotifyAuthService.shared
    @EnvironmentObject var shareHandler: SharedAlbumHandler
    
    var body: some View {
        TabView {

            SoundPrintView()
                .environmentObject(spotifyAuth)
                .tabItem {
                    Label("SoundPrint", systemImage: "waveform")
                }

            StudioSessionsView()
                .environmentObject(shareHandler)
                .tabItem {
                    Label("Studiosessions", systemImage: "music.note.list")
                }

            ProfileView()
                .environmentObject(spotifyAuth)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}
