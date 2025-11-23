import SwiftUI

struct RootAppView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        Group {
            switch authVM.authState {
            case .loading:
                ProgressView("Loading…")

            case .unauthenticated:
                AuthFlowView()

            case .authenticated:
                MainTabView()

            case .passwordReset:
                ResetPasswordView()
            }
        }
        .animation(.easeInOut, value: authVM.authState)
        .task {
            await authVM.loadInitialSession()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Check for session when app becomes active (e.g., after OAuth redirect)
                Task {
                    await authVM.checkForActiveSession()
                }
            }
        }
    }
}
