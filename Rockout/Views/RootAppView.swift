import SwiftUI
import Foundation

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
        
        // Handle: rockout://share/{token}
        if url.host == "share" {
            // Extract share token from path, handling spaces that might be inserted by messaging apps
            var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // Remove all whitespace from the token (iMessage sometimes adds spaces)
            path = path.replacingOccurrences(of: " ", with: "")
            path = path.replacingOccurrences(of: "\n", with: "")
            path = path.replacingOccurrences(of: "\t", with: "")
            
            // Final cleanup: trim any remaining whitespace
            let cleanToken = path.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !cleanToken.isEmpty {
                print("📎 Share link detected in RootAppView, token: \(cleanToken)")
                shareHandler.handleShareToken(cleanToken)
            } else {
                print("⚠️ Share link missing token. Original path: '\(url.path)'")
            }
        }
    }
    
}
