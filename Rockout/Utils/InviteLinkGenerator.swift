import Foundation

/// Utility for generating invite links for sharing the app
struct InviteLinkGenerator {
    // App Store URL - Update this with your actual App Store link when available
    private static let appStoreURL = "https://apps.apple.com/app/rockout" // Placeholder - update with actual URL
    
    // Deep link scheme
    private static let deepLinkScheme = "rockout"
    private static let deepLinkHost = "signup"
    
    /// Generates an invite link with optional referral code
    /// - Parameter userId: Optional user ID to use as referral code
    /// - Returns: URL string for the invite link
    static func generateInviteLink(userId: String? = nil) -> String {
        // Get current user ID if not provided
        let referralId = userId ?? getCurrentUserId()
        
        if let referralId = referralId {
            // Use deep link with referral
            return "\(deepLinkScheme)://\(deepLinkHost)?ref=\(referralId)"
        } else {
            // Fallback to App Store link
            return appStoreURL
        }
    }
    
    /// Generates a full invite message with link
    /// - Parameter userId: Optional user ID to use as referral code
    /// - Returns: Formatted invite message
    static func generateInviteMessage(userId: String? = nil) -> String {
        let link = generateInviteLink(userId: userId)
        return "Join me on RockOut! Download the app: \(link)"
    }
    
    /// Gets the current authenticated user's ID
    private static func getCurrentUserId() -> String? {
        // Try to get from Supabase auth
        if let userId = SupabaseService.shared.client.auth.currentUser?.id.uuidString {
            return userId
        }
        return nil
    }
}

