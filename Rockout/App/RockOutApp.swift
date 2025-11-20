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
                .onOpenURL { url in
                    // Handle Supabase Auth redirect (password reset / magic link / etc.)
                    authVM.handleDeepLink(url)
                }
        }
    }
}

struct RootAppView: View {
    @EnvironmentObject var authVM: AuthViewModel

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

            case .passwordReset:
                ResetPasswordView()
            }
        }
        .animation(.easeInOut, value: authVM.authState)
    }
}
