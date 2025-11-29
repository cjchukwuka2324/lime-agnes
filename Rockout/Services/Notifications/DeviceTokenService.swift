import Foundation
import Supabase

/// Service for managing APNs device tokens
final class DeviceTokenService {
    static let shared = DeviceTokenService()
    
    private let client = SupabaseService.shared.client
    
    private init() {}
    
    /// Register or update a device token for push notifications
    /// - Parameter token: The device token as a hex string
    func registerDeviceToken(_ token: String) async {
        do {
            guard let userId = client.auth.currentUser?.id else {
                print("⚠️ DeviceTokenService: No authenticated user, skipping token registration")
                return
            }
            
            print("📱 DeviceTokenService: Registering device token for user \(userId)")
            
            struct DeviceTokenRow: Encodable {
                let userId: String
                let token: String
                let platform: String
                let createdAt: String
                let updatedAt: String
                
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case token
                    case platform
                    case createdAt = "created_at"
                    case updatedAt = "updated_at"
                }
            }
            
            let now = Date()
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let nowString = isoFormatter.string(from: now)
            
            let row = DeviceTokenRow(
                userId: userId.uuidString,
                token: token,
                platform: "ios",
                createdAt: nowString,
                updatedAt: nowString
            )
            
            // Upsert the token (insert or update if exists)
            _ = try await client
                .from("device_tokens")
                .upsert(row, onConflict: "user_id,token")
                .execute()
            
            print("✅ DeviceTokenService: Successfully registered device token")
            
        } catch {
            print("❌ DeviceTokenService: Failed to register device token: \(error)")
            print("   Error details: \(error.localizedDescription)")
        }
    }
    
    /// Remove a device token (e.g., when logging out)
    /// - Parameter token: The device token to remove
    func unregisterDeviceToken(_ token: String) async {
        do {
            guard let userId = client.auth.currentUser?.id else {
                print("⚠️ DeviceTokenService: No authenticated user, skipping token unregistration")
                return
            }
            
            print("📱 DeviceTokenService: Unregistering device token for user \(userId)")
            
            try await client
                .from("device_tokens")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("token", value: token)
                .execute()
            
            print("✅ DeviceTokenService: Successfully unregistered device token")
            
        } catch {
            print("❌ DeviceTokenService: Failed to unregister device token: \(error)")
        }
    }
    
    /// Get all device tokens for the current user
    func getDeviceTokens() async throws -> [String] {
        guard let userId = client.auth.currentUser?.id else {
            throw NSError(domain: "DeviceTokenService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        struct TokenRow: Decodable {
            let token: String
        }
        
        let response = try await client
            .from("device_tokens")
            .select("token")
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        let decoder = JSONDecoder()
        let rows = try decoder.decode([TokenRow].self, from: response.data)
        
        return rows.map { $0.token }
    }
}

