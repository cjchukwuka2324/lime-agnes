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
        client = SupabaseClient(
            supabaseURL: URL(string: Secrets.supabaseUrl)!,
            supabaseKey: Secrets.supabaseAnonKey,
            options: options
        )
    }
}
