import Foundation
import Supabase

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

    // MUST match Supabase → Auth → URL Configuration
    private let passwordResetRedirectURL = URL(string: "rockout://password-reset")!

    init() {
        Task { await loadInitialSession() }
    }

    // MARK: - INITIAL SESSION
    func loadInitialSession() async {
        do {
            let session = try await supabase.auth.session
            currentUserEmail = session.user.email
            authState = .authenticated
        } catch {
            authState = .unauthenticated
        }
    }

    // MARK: - LOGIN
    func login(email: String, password: String) async throws {
        _ = try await supabase.auth.signIn(email: email, password: password)

        let session = try await supabase.auth.session
        currentUserEmail = session.user.email
        authState = .authenticated
    }

    // MARK: - SIGNUP
    func signup(email: String, password: String) async throws {
        _ = try await supabase.auth.signUp(email: email, password: password)
        // If confirm email required, the session may not be created yet.
    }

    // MARK: - LOGOUT
    func logout() async {
        do { try await supabase.auth.signOut() } catch {}
        currentUserEmail = nil
        authState = .unauthenticated
    }

    // MARK: - FORGOT PASSWORD
    func sendPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(
            email,
            redirectTo: passwordResetRedirectURL,
            captchaToken: nil
        )
    }

    // MARK: - DEEP LINK HANDLER (password reset etc.)
    func handleDeepLink(_ url: URL) {
        Task {
            do {
                let session = try await supabase.auth.session(from: url)
                currentUserEmail = session.user.email
                authState = .passwordReset
            } catch {
                print("Deep link failure:", error.localizedDescription)
            }
        }
    }

    // MARK: - UPDATE PASSWORD
    func updatePassword(to newPassword: String) async throws {
        try await supabase.auth.update(
            user: UserAttributes(password: newPassword)
        )

        let session = try await supabase.auth.session
        currentUserEmail = session.user.email
        authState = .authenticated
    }

    // MARK: - REFRESH USER
    func refreshUser() async {
        do {
            let session = try await supabase.auth.session
            currentUserEmail = session.user.email
        } catch {}
    }
}
