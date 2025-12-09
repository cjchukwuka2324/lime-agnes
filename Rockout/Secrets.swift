import Foundation

enum Secrets {
    // 🔥 Your Supabase base URL (NO trailing slash)
    static let supabaseUrl = "https://wklzogrfdrqluwchoqsp.supabase.co"

    // 🔥 Your Supabase anon public key (not service_role)
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndrbHpvZ3JmZHJxbHV3Y2hvcXNwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjMxMjAzNDcsImV4cCI6MjA3ODY5NjM0N30.HPrlq9hi2ab0YPsE5B8OibheLOmmNqmHKG2qRjt_3jY"
    
    // 🔥 Apple Music Developer Token (JWT) - Generate from Apple Developer account
    // See: https://developer.apple.com/documentation/applemusicapi/getting_keys_and_creating_tokens
    // TODO: Add your Apple Music developer token here
    static let appleMusicDeveloperToken: String? = nil
}
