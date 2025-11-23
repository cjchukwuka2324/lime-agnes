import Foundation
import Supabase

final class SpotifyConnectionService {
    static let shared = SpotifyConnectionService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Get User's Spotify Connection
    func getConnection() async throws -> SpotifyConnection? {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        do {
            let response = try await supabase
                .from("spotify_connections")
                .select()
                .eq("user_id", value: userId)
                .limit(1)
                .single()
                .execute()
            
            return try JSONDecoder().decode(SpotifyConnection.self, from: response.data)
        } catch {
            // No connection found
            return nil
        }
    }
    
    // MARK: - Save Spotify Connection
    func saveConnection(
        spotifyUserId: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        displayName: String? = nil,
        email: String? = nil
    ) async throws -> SpotifyConnection {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Check if connection exists
        if let existing = try? await getConnection() {
            // Update existing connection
            let dto = SpotifyConnectionDTO(
                user_id: userId,
                spotify_user_id: spotifyUserId,
                access_token: accessToken,
                refresh_token: refreshToken,
                expires_at: expiresAt.ISO8601Format(),
                display_name: displayName,
                email: email
            )
            
            let response = try await supabase
                .from("spotify_connections")
                .update(dto)
                .eq("user_id", value: userId)
                .select()
                .single()
                .execute()
            
            return try JSONDecoder().decode(SpotifyConnection.self, from: response.data)
        } else {
            // Create new connection
            let dto = SpotifyConnectionDTO(
                user_id: userId,
                spotify_user_id: spotifyUserId,
                access_token: accessToken,
                refresh_token: refreshToken,
                expires_at: expiresAt.ISO8601Format(),
                display_name: displayName,
                email: email
            )
            
            let response = try await supabase
                .from("spotify_connections")
                .insert(dto)
                .select()
                .single()
                .execute()
            
            return try JSONDecoder().decode(SpotifyConnection.self, from: response.data)
        }
    }
    
    // MARK: - Update Tokens
    func updateTokens(accessToken: String, refreshToken: String?, expiresAt: Date) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        struct TokenUpdate: Encodable {
            let access_token: String
            let refresh_token: String?
            let expires_at: String
        }
        
        let update = TokenUpdate(
            access_token: accessToken,
            refresh_token: refreshToken,
            expires_at: expiresAt.ISO8601Format()
        )
        
        try await supabase
            .from("spotify_connections")
            .update(update)
            .eq("user_id", value: userId)
            .execute()
    }
    
    // MARK: - Delete Connection
    func deleteConnection() async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        try await supabase
            .from("spotify_connections")
            .delete()
            .eq("user_id", value: userId)
            .execute()
    }
}

