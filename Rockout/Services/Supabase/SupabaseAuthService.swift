import Foundation
import Supabase

@MainActor
class SupabaseAuthService {

    let client = SupabaseService.shared.client

    func register(email: String, password: String) async throws {
        try await client.auth.signUp(email: email, password: password)
    }

    func login(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func logout() async throws {
        try await client.auth.signOut()
    }

    func getCurrentUser() -> Auth.User? {
        client.auth.currentUser
    }
}
