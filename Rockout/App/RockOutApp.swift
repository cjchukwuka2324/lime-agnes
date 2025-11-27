import SwiftUI

@main
struct RockoutApp: App {

    @StateObject private var authVM = AuthViewModel()

    init() {
        // RESTORED NAV BAR APPEARANCE — EXACT BEHAVIOR: BLACK BAR + WHITE CONTENT
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

        UINavigationBar.appearance().tintColor = .white // back button color
    }

    var body: some Scene {
        WindowGroup {
            RootAppView()
                .environmentObject(authVM)
                .environmentObject(SpotifyAuthService.shared)
                .onOpenURL { url in
                    // Handle Spotify OAuth redirect
                    if url.scheme == "rockout" && url.host == "spotify-callback" {
                        Task {
                            do {
                                try await SpotifyAuthService.shared.handleRedirect(url)
                                
                                // After successful authentication, trigger initial bootstrap ingestion
                                if SpotifyAuthService.shared.isAuthorized() {
                                    print("✅ Spotify authenticated, triggering RockList ingestion...")
                                    let dataService = RockListDataService.shared
                                    do {
                                        try await dataService.performInitialBootstrapIngestion()
                                        print("✅ Initial RockList ingestion completed from app redirect")
                                    } catch {
                                        print("⚠️ RockList ingestion error: \(error.localizedDescription)")
                                        // Don't block the UI - ingestion can happen in background
                                    }
                                }
                            } catch {
                                print("Spotify auth error: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        // Handle Supabase Auth redirect (password reset / magic link / etc.)
                        authVM.handleDeepLink(url)
                    }
                }
        }
    }
}

struct RootAppView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var spotifyAuth: SpotifyAuthService

    var body: some View {
        Group {
            switch authVM.authState {

            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…")
                        .foregroundColor(.secondary)
                }

            case .unauthenticated:
                AuthFlowView()   // Login / Signup tabs

            case .authenticated:
                MainTabView()    // Studio, SoundPrint, Profile
                    .task {
                        // Check and trigger RockList ingestion for existing users
                        // This runs when the authenticated view appears
                        if spotifyAuth.isAuthorized() {
                            await RockListDataService.shared.checkAndTriggerInitialIngestionIfNeeded()
                        }
                    }

            case .passwordReset:
                ResetPasswordView()
            }
        }
        .animation(.easeInOut, value: authVM.authState)
    }
}
