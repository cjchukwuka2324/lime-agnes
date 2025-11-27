import SwiftUI

@main
struct RockoutApp: App {

    @StateObject private var authVM = AuthViewModel()

    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black

        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 20, weight: .bold)
        ]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = .white
    }

    var body: some Scene {
        WindowGroup {
            RootAppView()
                .environmentObject(authVM)
                .onOpenURL { url in
                    print("🔥 Deep link received:", url.absoluteString)
                    
                    // Handle Spotify OAuth callback
                    if url.scheme == "rockout" && url.host == "auth" {
                        Task {
                            do {
                                try await SpotifyAuthService.shared.handleRedirectURL(url)
                            } catch {
                                print("❌ Failed to handle Spotify redirect: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        // Handle Supabase OAuth callback
                        authVM.handleDeepLink(url)
                    }
                }
        }
    }
}
