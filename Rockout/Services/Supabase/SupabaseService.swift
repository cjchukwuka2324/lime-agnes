
import Supabase
import Foundation

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        // Store these securely in the future using config files or environment variables.
        let supabaseURL = URL(string: "https://wklzogrfdrqluwchoqsp.supabase.co")!
        let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMxMjAzNDcsImV4cCI6MjA3ODY5NjM0N30.HPrlq9hi2ab0YPsE5B8OibheLOmmNqmHKG2qRjt_3jY" // shortened for clarity

        self.client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey
        )
    }
}
