import SwiftUI

@main
struct RockOutApp: App {
    @StateObject private var authService = SpotifyAuthService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .onOpenURL { url in
                    Task {
                        await authService.handleRedirectURL(url)
                    }
                }
        }
    }
}
