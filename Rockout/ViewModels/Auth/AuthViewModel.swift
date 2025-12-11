import Foundation
import Supabase
import UIKit
import AuthenticationServices

@MainActor
final class AuthViewModel: ObservableObject {

    enum AuthState {
        case loading
        case unauthenticated
        case authenticated
        case passwordReset
    }

    @Published var authState: AuthState = .loading
    @Published var currentUserEmail: String?
    @Published var hasUsername: Bool? = nil // nil = loading/unknown, true = has username, false = missing username
    @Published var shouldShowProfile: Bool = false // Flag to navigate to profile tab after username setup

    private var supabase: SupabaseClient {
        SupabaseService.shared.client
    }

    private let oauthRedirectURL = URL(string: "rockout://auth/callback")!
    private let passwordResetRedirectURL = URL(string: "rockout://password-reset")!

    init() {
        Task { await loadInitialSession() }
        
        // Listen for session restoration notifications from AppDelegate
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SessionRestored"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForActiveSession()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func loadInitialSession() async {
        do {
            let session = try await supabase.auth.session
            currentUserEmail = session.user.email
            authState = .authenticated
            // Check username status after authentication
            await checkUsernameStatus()
        } catch {
            authState = .unauthenticated
            hasUsername = nil
        }
    }

    // MARK: - Google OAuth
    func loginWithGoogle() {
        Task { @MainActor in
            do {
                print("🌐 Starting Supabase Mobile OAuth (Google)…")

                // With PKCE flow, signInWithOAuth should automatically open the browser
                // The result type varies - it might be a Session if already authenticated
                // or it might trigger the OAuth flow via ASWebAuthenticationSession
                _ = try await supabase.auth.signInWithOAuth(
                    provider: .google,
                    redirectTo: oauthRedirectURL
                )

                print("➡️ OAuth flow initiated - browser should open automatically")
                // The OAuth callback will be handled via handleDeepLink when user completes auth

            } catch {
                print("❌ Google OAuth failed:", error)
                print("❌ Error details:", error.localizedDescription)
            }
        }
    }

    // MARK: - Deep Link Handler
    func handleDeepLink(_ url: URL) {
        print("🔥 Deep link received:", url.absoluteString)
        print("   Full URL: \(url.absoluteString)")
        print("   Host: \(url.host ?? "nil")")
        print("   Path: \(url.path)")
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            print("   Query items: \(queryItems)")
        }

        Task { @MainActor in
            // Handle email confirmation and password reset links
            // These come in as: rockout://auth/callback or rockout://password-reset
            // with access_token and refresh_token in query parameters
            if url.host == "auth" || url.host == "password-reset" || url.path.contains("auth/callback") {
                do {
                    // Try to restore session from URL (works for email confirmation and password reset)
                    let session = try await supabase.auth.session(from: url)
                    print("✅ Session restored from URL for:", session.user.email ?? "nil")
                    currentUserEmail = session.user.email
                    authState = .authenticated
                    print("✅ Auth state updated to authenticated")
                    
                    // Refresh profile data after successful authentication
                    // This will also check for and apply any stored signup data
                    Task {
                        do {
                            _ = try await UserProfileService.shared.getCurrentUserProfile()
                            print("✅ Profile refreshed after email confirmation")
                            // Check username status after profile refresh
                            await self.checkUsernameStatus()
                        } catch {
                            print("⚠️ Failed to refresh profile after email confirmation: \(error.localizedDescription)")
                        }
                    }
                    return
                } catch {
                    print("⚠️ Could not restore session from URL:", error.localizedDescription)
                    // Continue to fallback below
                }
            }
            
            // Fallback: Check if session was already stored (with retry)
            await checkForActiveSessionWithRetry()
            
            // If we successfully got a session, refresh profile
            // This will also check for and apply any stored signup data
            if authState == .authenticated {
                Task {
                    do {
                        _ = try await UserProfileService.shared.getCurrentUserProfile()
                        print("✅ Profile refreshed after session check")
                        // Check username status after profile refresh
                        await self.checkUsernameStatus()
                    } catch {
                        print("⚠️ Failed to refresh profile: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // Check for active session (useful when app becomes active)
    func checkForActiveSession() async {
        do {
            let session = try await supabase.auth.session
            if session.user != nil {
                print("✅ Found active session on check")
                currentUserEmail = session.user.email
                authState = .authenticated
                // Check username status after authentication
                await checkUsernameStatus()
            } else {
                print("⚠️ No active session found")
                hasUsername = nil
            }
        } catch {
            print("⚠️ No session available:", error.localizedDescription)
            hasUsername = nil
        }
    }
    
    // Check for active session with retry (for OAuth callbacks)
    private func checkForActiveSessionWithRetry() async {
        // Try immediately
        await checkForActiveSession()
        
        // If not found, wait a bit and try again (session might still be writing)
        if authState != .authenticated {
            try? await Task.sleep(for: .milliseconds(500))
            await checkForActiveSession()
        }
        
        // One more retry after a longer delay
        if authState != .authenticated {
            try? await Task.sleep(for: .milliseconds(1000))
            await checkForActiveSession()
        }
    }

    func logout() async {
        try? await supabase.auth.signOut()
        currentUserEmail = nil
        authState = .unauthenticated
        hasUsername = nil
        shouldShowProfile = false
        // Reset onboarding so it shows again after logout
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }

    func refreshUser() async {
        do {
            let session = try await supabase.auth.session
            currentUserEmail = session.user.email
        } catch {}
    }
    
    // MARK: - Email/Password Auth
    func login(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        currentUserEmail = session.user.email
        authState = .authenticated
        // Check username status after login
        await checkUsernameStatus()
    }
    
    func signup(email: String, password: String) async throws -> UUID {
        let response = try await supabase.auth.signUp(email: email, password: password)
        // Return the user ID from the signup response
        return response.user.id
    }
    
    func sendPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email, redirectTo: passwordResetRedirectURL)
    }
    
    func updatePassword(to newPassword: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: newPassword))
        // After password update, refresh the session
        let session = try await supabase.auth.session
        currentUserEmail = session.user.email
        authState = .authenticated
    }
    
    // MARK: - Username Status Check
    func checkUsernameStatus() async {
        guard authState == .authenticated else {
            hasUsername = nil
            return
        }
        
        do {
            let profile = try await UserProfileService.shared.getCurrentUserProfile()
            // Check if username exists and is not empty
            if let username = profile?.username, !username.trimmingCharacters(in: .whitespaces).isEmpty {
                hasUsername = true
                print("✅ User has username: @\(username)")
            } else {
                hasUsername = false
                print("⚠️ User does not have a username")
            }
        } catch {
            print("⚠️ Failed to check username status: \(error.localizedDescription)")
            // On error, assume username is missing to be safe
            hasUsername = false
        }
    }
}

// Helper class for ASWebAuthenticationSession presentation context
class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Get the key window from the active scene
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                if let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                    return window
                }
                if let window = windowScene.windows.first {
                    return window
                }
            }
        }
        // This shouldn't happen, but provide a fallback
        return UIWindow()
    }
}
