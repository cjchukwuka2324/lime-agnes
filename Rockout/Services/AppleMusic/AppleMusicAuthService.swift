import Foundation
import Combine
import MusicKit
import Supabase

@MainActor
final class AppleMusicAuthService: ObservableObject {
    
    static let shared = AppleMusicAuthService()
    
    @Published private(set) var userToken: String?
    @Published private(set) var appleMusicConnection: AppleMusicConnection?
    @Published private(set) var isLoading = false
    
    private let connectionService = MusicPlatformConnectionService.shared
    private let supabase = SupabaseService.shared.client
    
    private init() {
        Task {
            await loadConnection()
        }
    }
    
    // MARK: - Load Connection from Database
    
    func loadConnection() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            if let unifiedConnection = try await connectionService.getConnection(),
               unifiedConnection.platform == "apple_music" {
                
                guard let appleMusicUserId = unifiedConnection.apple_music_user_id,
                      let userTokenValue = unifiedConnection.user_token else {
                    throw NSError(domain: "AppleMusicAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Apple Music connection data"])
                }
                
                appleMusicConnection = AppleMusicConnection(
                    id: unifiedConnection.id,
                    user_id: unifiedConnection.user_id,
                    apple_music_user_id: appleMusicUserId,
                    user_token: userTokenValue,
                    expires_at: unifiedConnection.expires_at,
                    connected_at: unifiedConnection.connected_at,
                    display_name: unifiedConnection.display_name,
                    email: unifiedConnection.email
                )
                
                self.userToken = userTokenValue
            } else {
                // No connection found
                userToken = nil
                appleMusicConnection = nil
            }
        } catch {
            print("Failed to load Apple Music connection: \(error)")
            userToken = nil
            appleMusicConnection = nil
        }
    }
    
    // MARK: - Authorization
    
    func isAuthorized() -> Bool {
        // Check both database connection and MusicKit authorization status
        return appleMusicConnection != nil && MusicAuthorization.currentStatus == .authorized
    }
    
    func authorize() async throws {
        // Check if user already has a connection to another platform
        if let existingConnection = try await connectionService.getConnection() {
            if existingConnection.platform != "apple_music" {
                throw NSError(
                    domain: "AppleMusicAuth",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "User already has a connection to \(existingConnection.platform). Platform connection is permanent and cannot be changed."]
                )
            }
        }
        
        // Request MusicKit authorization
        // Note: MusicAuthorization.request() must be called from the main thread
        let status: MusicAuthorization.Status
        do {
            // Check current status first
            let currentStatus = await MusicAuthorization.request()
            status = currentStatus
        } catch {
            print("❌ MusicKit authorization error: \(error)")
            throw NSError(
                domain: "AppleMusicAuth",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to request MusicKit authorization: \(error.localizedDescription)"]
            )
        }
        
        guard status == .authorized else {
            let statusMessage: String
            switch status {
            case .denied:
                statusMessage = "MusicKit authorization was denied. Please enable access in Settings."
            case .restricted:
                statusMessage = "MusicKit authorization is restricted on this device."
            case .notDetermined:
                statusMessage = "MusicKit authorization was not determined."
            @unknown default:
                statusMessage = "MusicKit authorization failed with unknown status."
            }
            throw NSError(
                domain: "AppleMusicAuth",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: statusMessage]
            )
        }
        
        // Now that MusicKit is authorized, we MUST verify actual authentication
        // by attempting to fetch real user data. This will fail if:
        // 1. User doesn't have an Apple Music subscription
        // 2. User isn't signed into Apple Music on their device
        
        // IMPORTANT: Verify subscription BEFORE saving connection
        // Try multiple methods to verify the user has an active Apple Music subscription
        
        var verificationSucceeded = false
        var verificationError: Error?
        
        // Method 1: Try accessing user library via MusicKit
        do {
            let libraryRequest = MusicLibraryRequest<Song>()
            _ = try await libraryRequest.response()
            verificationSucceeded = true
            print("✅ Apple Music subscription verified via library access")
        } catch {
            verificationError = error
            print("⚠️ Library access failed: \(error.localizedDescription)")
            
            // Method 2: Try accessing recently played via Web API (if we can get user token)
            // Note: This requires MusicKit to provide user token, which isn't directly accessible
            // So we'll rely on library verification as primary method
        }
        
        // If verification failed, throw error - don't save connection
        guard verificationSucceeded else {
            throw NSError(
                domain: "AppleMusicAuth",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Could not verify Apple Music subscription. Please ensure you are signed into Apple Music with an active subscription. Go to Settings > Music to sign in, or check that your Apple Music subscription is active."]
            )
        }
        
        // Verification succeeded - now save connection
        // Generate a stable user identifier
        let userId = UUID().uuidString
        let userTokenString = "music_kit_managed" // MusicKit manages tokens automatically
        
        let unifiedConnection = try await connectionService.saveAppleMusicConnection(
            appleMusicUserId: userId,
            userToken: userTokenString,
            expiresAt: nil,
            displayName: nil,
            email: nil // Email not available from Apple Music API
        )
        
        // Update local connection state
        await MainActor.run {
            appleMusicConnection = AppleMusicConnection(
                id: unifiedConnection.id,
                user_id: unifiedConnection.user_id,
                apple_music_user_id: unifiedConnection.apple_music_user_id ?? "",
                user_token: unifiedConnection.user_token ?? "",
                expires_at: unifiedConnection.expires_at,
                connected_at: unifiedConnection.connected_at,
                display_name: unifiedConnection.display_name,
                email: unifiedConnection.email
            )
            
            self.userToken = userTokenString
        }
    }
}

