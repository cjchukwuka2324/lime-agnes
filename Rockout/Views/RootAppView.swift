import SwiftUI

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
            handleDeepLink(url: url)
        }
    }
    
    private func handleDeepLink(url: URL) {
        guard url.scheme == "rockout" else { return }
        
        // Handle: rockout://share/{token}
        if url.host == "share" {
            // Extract share token from path
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                shareHandler.handleShareToken(path)
            }
        }
    }
}
