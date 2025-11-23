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

    private let supabase = SupabaseService.shared.client

    private let oauthRedirectURL = URL(string: "rockout://auth/callback")!
    private let passwordResetRedirectURL = URL(string: "rockout://password-reset")!

    init() {
        Task { await loadInitialSession() }
    }

    func loadInitialSession() async {
        do {
            let session = try await supabase.auth.session
            currentUserEmail = session.user.email
            authState = .authenticated
        } catch {
            authState = .unauthenticated
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

        Task { @MainActor in
            // First try to restore session from URL
            do {
                let session = try await supabase.auth.session(from: url)
                print("✅ OAuth session restored from URL for:", session.user.email ?? "nil")
                currentUserEmail = session.user.email
                authState = .authenticated
                print("✅ Auth state updated to authenticated")
                return
            } catch {
                print("⚠️ Could not restore session from URL:", error.localizedDescription)
            }
            
            // Fallback: Check if session was already stored (with retry)
            await checkForActiveSessionWithRetry()
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
            } else {
                print("⚠️ No active session found")
            }
        } catch {
            print("⚠️ No session available:", error.localizedDescription)
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
    }
    
    func signup(email: String, password: String) async throws {
        try await supabase.auth.signUp(email: email, password: password)
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
