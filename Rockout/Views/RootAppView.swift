import SwiftUI
import Foundation
import Supabase

struct RootAppView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var shareHandler = SharedAlbumHandler.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var hasCheckedOnAppLaunch = false

    var body: some View {
        Group {
            // Show onboarding if not completed (first-time users, after logout, or when trying to sign up/sign in)
            if !hasCompletedOnboarding {
                OnboardingFlowView(hasCompletedOnboarding: $hasCompletedOnboarding)
            } else {
                // Existing auth flow
                switch authVM.authState {
                case .loading:
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .unauthenticated:
                    // User is unauthenticated - show auth flow
                    // Onboarding will show if they haven't completed it (handled above)
                    AuthFlowView()

                case .authenticated:
                    // Check if user has username - show SetUsernameView if missing
                    // Show loading state while checking username status
                    if authVM.hasUsername == nil {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                    } else if authVM.hasUsername == false {
                        SetUsernameView()
                            .environmentObject(authVM)
                    } else {
                        MainTabView()
                            .environmentObject(shareHandler)
                            .environmentObject(authVM)
                            .task {
                                // Load feed on app startup when authenticated
                                await loadFeedOnStartup()
                            }
                    }
                        
                case .passwordReset:
                    ResetPasswordView()
                }
            }
        }
        .animation(.easeInOut, value: authVM.authState)
        .task {
            await authVM.checkForActiveSession()
            // On app launch, if user is unauthenticated, reset onboarding
            // This allows onboarding to restart if user refreshes app while on login screen
            if !hasCheckedOnAppLaunch {
                hasCheckedOnAppLaunch = true
                if authVM.authState == .unauthenticated {
                    hasCompletedOnboarding = false
                }
            }
            // Check username status if authenticated
            if authVM.authState == .authenticated {
                await authVM.checkUsernameStatus()
            }
        }
        .onChange(of: authVM.authState) { oldState, newState in
            // When user becomes authenticated, ensure we're registered for remote notifications
            // This handles the case where user logs in after app launch
            if newState == .authenticated && oldState != .authenticated {
                // Re-register for remote notifications to ensure token is registered
                // This is safe to call multiple times - iOS will only call the delegate once per token
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                    print("✅ User authenticated - re-registering for remote notifications")
                }
                // Check username status when user becomes authenticated
                Task {
                    await authVM.checkUsernameStatus()
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // Check for session when app becomes active (e.g., after OAuth redirect)
                Task {
                    await authVM.checkForActiveSession()
                    // If app becomes active and user is unauthenticated, reset onboarding
                    // This handles app refresh/restart while on login screen
                    if authVM.authState == .unauthenticated {
                        hasCompletedOnboarding = false
                    } else if authVM.authState == .authenticated {
                        // Check username status when app becomes active and user is authenticated
                        await authVM.checkUsernameStatus()
                    }
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
        
        // Handle auth callbacks: rockout://auth/callback (email confirmation) or rockout://auth (OAuth)
        if url.host == "auth" {
            // Check if this is an email confirmation link (has callback path or query params)
            if url.path.contains("callback") || url.query != nil {
                // This is likely an email confirmation or password reset link
                // Handle via AuthViewModel which will restore session
                authVM.handleDeepLink(url)
            } else {
                // Spotify OAuth is handled in RockOutApp
                return
            }
        }
        
        // Handle password reset: rockout://password-reset
        if url.host == "password-reset" || url.path.contains("password-reset") {
            authVM.handleDeepLink(url)
            return
        }
        
        // Handle signup invite links: rockout://signup?ref={userId}
        if url.host == "signup" {
            // Extract referral ID from query parameters
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let refId = queryItems.first(where: { $0.name == "ref" })?.value {
                print("📧 Signup invite link detected with referral: \(refId)")
                // TODO: Track referral and navigate to signup screen if needed
                // For now, just log it - the app will handle signup normally
            }
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
