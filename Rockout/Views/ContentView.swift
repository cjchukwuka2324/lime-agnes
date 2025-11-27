import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: SpotifyAuthService

    var body: some View {
        Group {
            if authService.isAuthorized() {
                SoundPrintView()
            } else {
                ConnectSpotifyView()
            }
        }
        .animation(.easeInOut, value: authService.isAuthorized())
    }
}
