import SwiftUI
import Foundation
import Supabase

struct RootAppView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var shareHandler = SharedAlbumHandler.shared

    var body: some View {
        Group {
            switch authVM.authState {
            case .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .unauthenticated:
                AuthFlowView()

            case .authenticated:
                MainTabView()
                    .environmentObject(shareHandler)
                    .task {
                        // Load feed on app startup when authenticated
                        await loadFeedOnStartup()
                    }
                    
            case .passwordReset:
                ResetPasswordView()
            }
        }
        .animation(.easeInOut, value: authVM.authState)
        .task {
            await authVM.checkForActiveSession()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Check for session when app becomes active (e.g., after OAuth redirect)
                Task {
                    await authVM.checkForActiveSession()
                }
            }
        }
        .onOpenURL { url in
            print("📱 onOpenURL in RootAppView: \(url.absoluteString)")
            handleDeepLink(url: url)
        }
    }
    
    private func handleDeepLink(url: URL) {
        guard url.scheme == "rockout" else { return }
        
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
                print("📎 Share link detected in RootAppView (\(host)), token: \(cleanToken)")
                shareHandler.handleShareToken(cleanToken)
            } else {
                print("⚠️ Share link missing token. Original path: '\(url.path)'")
            }
            return
        }
        
        // Handle Spotify OAuth callback: rockout://auth
        if url.host == "auth" {
            // Spotify OAuth is handled in RockOutApp
            return
        }
    }
    
    private func loadFeedOnStartup() async {
        // Load feed on app startup to ensure old posts are available
        let feedService = SupabaseFeedService.shared
        do {
            _ = try await feedService.fetchHomeFeed(feedType: .forYou, region: nil)
            print("✅ Feed loaded on app startup")
        } catch {
            print("⚠️ Failed to load feed on startup: \(error.localizedDescription)")
        }
    }
    
}
