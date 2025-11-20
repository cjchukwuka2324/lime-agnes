import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {

            SoundPrintView()
                .tabItem {
                    Label("SoundPrint", systemImage: "waveform")
                }
            
            StudioSessionsView()
                .tabItem {
                    Label("Studiosessions", systemImage: "music.note.list")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
    }
}
