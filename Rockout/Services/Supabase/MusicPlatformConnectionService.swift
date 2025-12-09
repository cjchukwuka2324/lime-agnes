import Foundation
import Supabase

final class MusicPlatformConnectionService {
    static let shared = MusicPlatformConnectionService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Models
    
    struct MusicPlatformConnection: Codable, Identifiable {
        let id: UUID
        let user_id: UUID
        let platform: String // 'spotify' or 'apple_music'
        let spotify_user_id: String?
        let access_token: String?
        let refresh_token: String?
        let apple_music_user_id: String?
        let user_token: String? // MusicKit user token
        let expires_at: String?
        let connected_at: String
        let display_name: String?
        let email: String?
    }
    
    struct SpotifyConnectionDTO: Encodable {
        let user_id: String
        let platform: String
        let spotify_user_id: String
        let access_token: String
        let refresh_token: String
        let expires_at: String
        let display_name: String?
        let email: String?
    }
    
    struct AppleMusicConnectionDTO: Encodable {
        let user_id: String
        let platform: String
        let apple_music_user_id: String
        let user_token: String
        let expires_at: String?
        let display_name: String?
        let email: String?
    }
    
    // MARK: - Get User's Connection
    
    func getConnection() async throws -> MusicPlatformConnection? {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        do {
            let response = try await supabase
                .from("music_platform_connections")
                .select()
                .eq("user_id", value: userId)
                .limit(1)
                .single()
                .execute()
            
            return try JSONDecoder().decode(MusicPlatformConnection.self, from: response.data)
        } catch {
            // No connection found - check legacy spotify_connections for backward compatibility
            if let legacyConnection = try? await getLegacySpotifyConnection() {
                // Migrate to new table
                return try await migrateLegacyConnection(legacyConnection)
            }
            return nil
        }
    }
    
    // MARK: - Check for Existing Connection
    
    func hasAnyConnection() async throws -> Bool {
        let connection = try await getConnection()
        return connection != nil
    }
    
    func getPlatform() async throws -> String? {
        let connection = try await getConnection()
        return connection?.platform
    }
    
    // MARK: - Save Spotify Connection
    
    func saveSpotifyConnection(
        spotifyUserId: String,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        displayName: String? = nil,
        email: String? = nil
    ) async throws -> MusicPlatformConnection {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Check if user already has a connection (to enforce one-platform-per-user)
        if let existingConnection = try await getConnection() {
            if existingConnection.platform != "spotify" {
                throw NSError(
                    domain: "MusicPlatformConnectionService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "User already has a connection to \(existingConnection.platform). Platform connection is permanent and cannot be changed."]
                )
            }
            // Update existing Spotify connection
            return try await updateSpotifyConnection(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                displayName: displayName,
                email: email
            )
        }
        
        let dto = SpotifyConnectionDTO(
            user_id: userId,
            platform: "spotify",
            spotify_user_id: spotifyUserId,
            access_token: accessToken,
            refresh_token: refreshToken,
            expires_at: expiresAt.ISO8601Format(),
            display_name: displayName,
            email: email
        )
        
        let response = try await supabase
            .from("music_platform_connections")
            .insert(dto)
            .select()
            .single()
            .execute()
        
        return try JSONDecoder().decode(MusicPlatformConnection.self, from: response.data)
    }
    
    // MARK: - Save Apple Music Connection
    
    func saveAppleMusicConnection(
        appleMusicUserId: String,
        userToken: String,
        expiresAt: Date? = nil,
        displayName: String? = nil,
        email: String? = nil
    ) async throws -> MusicPlatformConnection {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Check if user already has a connection (to enforce one-platform-per-user)
        if let existingConnection = try await getConnection() {
            if existingConnection.platform != "apple_music" {
                throw NSError(
                    domain: "MusicPlatformConnectionService",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "User already has a connection to \(existingConnection.platform). Platform connection is permanent and cannot be changed."]
                )
            }
            // Update existing Apple Music connection
            return try await updateAppleMusicConnection(
                userToken: userToken,
                expiresAt: expiresAt,
                displayName: displayName,
                email: email
            )
        }
        
        let dto = AppleMusicConnectionDTO(
            user_id: userId,
            platform: "apple_music",
            apple_music_user_id: appleMusicUserId,
            user_token: userToken,
            expires_at: expiresAt?.ISO8601Format(),
            display_name: displayName,
            email: email
        )
        
        let response = try await supabase
            .from("music_platform_connections")
            .insert(dto)
            .select()
            .single()
            .execute()
        
        return try JSONDecoder().decode(MusicPlatformConnection.self, from: response.data)
    }
    
    // MARK: - Update Connections
    
    func updateSpotifyConnection(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date,
        displayName: String? = nil,
        email: String? = nil
    ) async throws -> MusicPlatformConnection {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        struct TokenUpdate: Encodable {
            let access_token: String
            let refresh_token: String?
            let expires_at: String
            let display_name: String?
            let email: String?
        }
        
        let update = TokenUpdate(
            access_token: accessToken,
            refresh_token: refreshToken,
            expires_at: expiresAt.ISO8601Format(),
            display_name: displayName,
            email: email
        )
        
        let response = try await supabase
            .from("music_platform_connections")
            .update(update)
            .eq("user_id", value: userId)
            .select()
            .single()
            .execute()
        
        return try JSONDecoder().decode(MusicPlatformConnection.self, from: response.data)
    }
    
    func updateAppleMusicConnection(
        userToken: String,
        expiresAt: Date? = nil,
        displayName: String? = nil,
        email: String? = nil
    ) async throws -> MusicPlatformConnection {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        struct TokenUpdate: Encodable {
            let user_token: String
            let expires_at: String?
            let display_name: String?
            let email: String?
        }
        
        let update = TokenUpdate(
            user_token: userToken,
            expires_at: expiresAt?.ISO8601Format(),
            display_name: displayName,
            email: email
        )
        
        let response = try await supabase
            .from("music_platform_connections")
            .update(update)
            .eq("user_id", value: userId)
            .select()
            .single()
            .execute()
        
        return try JSONDecoder().decode(MusicPlatformConnection.self, from: response.data)
    }
    
    // MARK: - Legacy Support (Migration Helper)
    
    private func getLegacySpotifyConnection() async throws -> SpotifyConnection? {
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
            return nil
        }
    }
    
    private func migrateLegacyConnection(_ legacy: SpotifyConnection) async throws -> MusicPlatformConnection {
        let formatter = ISO8601DateFormatter()
        let expiresAt = formatter.date(from: legacy.expires_at) ?? Date().addingTimeInterval(3600)
        
        return try await saveSpotifyConnection(
            spotifyUserId: legacy.spotify_user_id,
            accessToken: legacy.access_token,
            refreshToken: legacy.refresh_token,
            expiresAt: expiresAt,
            displayName: legacy.display_name,
            email: legacy.email
        )
    }
}

