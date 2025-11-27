import Supabase
import Foundation

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {

        // AUTH CONFIG — using correct initializer
        let authOptions = SupabaseClientOptions.AuthOptions(
            storage: AuthClient.Configuration.defaultLocalStorage,
            redirectToURL: URL(string: "rockout://auth/callback"),
            flowType: .pkce,
            autoRefreshToken: true,
            emitLocalSessionAsInitialSession: true
        )

        // SUPABASE CLIENT OPTIONS
        let options = SupabaseClientOptions(
            db: .init(),
            auth: authOptions,
            global: .init(),
            functions: .init(),
            realtime: .init(),
            storage: .init()
        )

        // FINALLY THE CLIENT
        guard let supabaseURL = URL(string: Secrets.supabaseUrl) else {
            print("❌ ERROR: Invalid Supabase URL in Secrets.swift: \(Secrets.supabaseUrl)")
            // Use a dummy URL to prevent crash - will fail gracefully later
            let dummyURL = URL(string: "https://invalid.supabase.co")!
            client = SupabaseClient(
                supabaseURL: dummyURL,
                supabaseKey: "invalid",
                options: options
            )
            print("⚠️ Using dummy Supabase client - app may not work correctly")
            return
        }
        
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: Secrets.supabaseAnonKey,
            options: options
        )
    }
}
