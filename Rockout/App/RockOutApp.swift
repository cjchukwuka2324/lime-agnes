import SwiftUI

@main
struct RockoutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
                    print("🔥 Deep link received in App: \(url.absoluteString)")
                    print("   Scheme: \(url.scheme ?? "nil"), Host: \(url.host ?? "nil"), Path: \(url.path)")
                    print("   Full URL components: \(url)")
                    
                    guard url.scheme == "rockout" else {
                        print("⚠️ Unknown URL scheme: \(url.scheme ?? "nil")")
                        return
                    }
                    
                    // Handle share links: rockout://share/{token}
                    if url.host == "share" {
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
                            print("📎 Share link detected in App, token: \(cleanToken)")
                            // Use MainActor to ensure UI updates happen on main thread
                            Task { @MainActor in
                                SharedAlbumHandler.shared.handleShareToken(cleanToken)
                            }
                        } else {
                            print("⚠️ Share link missing token. Original path: '\(url.path)'")
                        }
                        return
                    }
                    
                    // Handle Spotify OAuth callback: rockout://auth
                    if url.host == "auth" {
                        Task {
                            do {
                                try await SpotifyAuthService.shared.handleRedirectURL(url)
                                print("✅ Spotify OAuth successful")
                            } catch {
                                print("❌ Failed to handle Spotify redirect: \(error.localizedDescription)")
                            }
                        }
                        return
                    }
                    
                    // Handle Supabase OAuth callback (fallback)
                    print("🔐 Handling as Supabase OAuth callback")
                    authVM.handleDeepLink(url)
                }
        }
    }
}
