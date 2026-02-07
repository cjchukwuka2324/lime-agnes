import SwiftUI

@main
struct RockoutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authVM = AuthViewModel()

    init() {
            // Configure Navigation Bar Appearance
            let navAppearance = UINavigationBarAppearance()
            navAppearance.configureWithOpaqueBackground()
            navAppearance.backgroundColor = UIColor.black

            navAppearance.titleTextAttributes = [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 20, weight: .bold)
            ]

            UINavigationBar.appearance().standardAppearance = navAppearance
            UINavigationBar.appearance().compactAppearance = navAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
            UINavigationBar.appearance().tintColor = .white
            
            // Configure Tab Bar Appearance
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithOpaqueBackground()
            tabBarAppearance.backgroundColor = UIColor.black
            
            tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
            tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.white.withAlphaComponent(0.6)]
            
            tabBarAppearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
            tabBarAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
            
            UITabBar.appearance().standardAppearance = tabBarAppearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
            }
        }

    var body: some Scene {
        WindowGroup {
            RootAppView()
                .environmentObject(authVM)
                .onOpenURL { url in
                    Logger.general.info("Deep link received in App: \(url.absoluteString)")
                    Logger.general.debug("Scheme: \(url.scheme ?? "nil"), Host: \(url.host ?? "nil"), Path: \(url.path)")
                    Logger.general.debug("Full URL components: \(url)")
                    
                    guard url.scheme == "rockout" else {
                        Logger.general.warning("Unknown URL scheme: \(url.scheme ?? "nil")")
                        return
                    }
                    
                    // Handle share links:
                    //   rockout://share/{token}       (legacy)
                    //   rockout://view/{token}        (view-only)
                    //   rockout://collaborate/{token} (collaboration)
                    if let host = url.host, ["share", "view", "collaborate"].contains(host) {
                        // Extract token from path, handling spaces that might be inserted by messaging apps
                        var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        // Remove all whitespace from the token (iMessage sometimes adds spaces)
                        path = path.replacingOccurrences(of: " ", with: "")
                        path = path.replacingOccurrences(of: "\n", with: "")
                        path = path.replacingOccurrences(of: "\t", with: "")
                        
                        // Also check if token is in the host or path components
                        let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
                        let token = components.first ?? path
                        
                        // Final cleanup: trim any remaining whitespace
                        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if !cleanToken.isEmpty {
                            Logger.general.info("Share link detected in App (\(host)), token: \(cleanToken)")
                            // Use MainActor to ensure UI updates happen on main thread
                            Task { @MainActor in
                                SharedAlbumHandler.shared.handleShareToken(cleanToken)
                            }
                        } else {
                            Logger.general.warning("Share link missing token. Original path: '\(url.path)'")
                        }
                        return
                    }
                    
                    // Handle auth callbacks: rockout://auth/callback (email confirmation) or rockout://auth (OAuth)
                    if url.host == "auth" {
                        // Check if this is an email confirmation link (has callback path or query params)
                        if url.path.contains("callback") || url.query != nil {
                            // This is likely an email confirmation or password reset link
                            // Handle via AuthViewModel which will restore session
                            Logger.auth.info("Handling as email confirmation/password reset link")
                            authVM.handleDeepLink(url)
                        } else {
                            // Spotify OAuth callback
                            Task {
                                do {
                                    try await SpotifyAuthService.shared.handleRedirectURL(url)
                                    Logger.spotify.success("Spotify OAuth successful")
                                } catch {
                                    Logger.spotify.failure("Failed to handle Spotify redirect", error: error)
                                }
                            }
                        }
                        return
                    }
                    
                    // Handle password reset: rockout://password-reset
                    if url.host == "password-reset" || url.path.contains("password-reset") {
                        Logger.auth.info("Handling as password reset link")
                        authVM.handleDeepLink(url)
                        return
                    }
                    
                    // Handle Supabase OAuth callback (fallback)
                    Logger.auth.info("Handling as Supabase OAuth callback")
                    authVM.handleDeepLink(url)
                }
        }
    }
}
