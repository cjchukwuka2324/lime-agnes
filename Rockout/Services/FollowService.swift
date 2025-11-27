import Foundation
import Supabase

@MainActor
class FollowService {
    static let shared = FollowService()
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    func follow(userId: UUID) async throws {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "FollowService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard currentUserId != userId else {
            throw NSError(domain: "FollowService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Cannot follow yourself"])
        }
        
        try await supabase
            .from("user_follows")
            .insert([
                "follower_id": currentUserId.uuidString,
                "followed_id": userId.uuidString
            ])
            .execute()
        
        // Create notification for follow
        if let currentUserProfile = try? await UserProfileService.shared.getCurrentUserProfile() {
            let displayName: String
            if let firstName = currentUserProfile.firstName, let lastName = currentUserProfile.lastName {
                displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            } else if let displayNameValue = currentUserProfile.displayName, !displayNameValue.isEmpty {
                displayName = displayNameValue
            } else {
                let email = supabase.auth.currentUser?.email ?? "User"
                displayName = email.components(separatedBy: "@").first ?? "User"
            }
            
            let handle: String
            if let email = supabase.auth.currentUser?.email {
                let emailPrefix = email.components(separatedBy: "@").first ?? "user"
                handle = "@\(emailPrefix)"
            } else if let firstName = currentUserProfile.firstName {
                handle = "@\(firstName.lowercased())"
            } else {
                handle = "@user"
            }
            
            let initials: String
            if let firstName = currentUserProfile.firstName, let lastName = currentUserProfile.lastName {
                let firstInitial = String(firstName.prefix(1)).uppercased()
                let lastInitial = String(lastName.prefix(1)).uppercased()
                initials = "\(firstInitial)\(lastInitial)"
            } else {
                initials = String(displayName.prefix(2)).uppercased()
            }
            
            let fromUser = UserSummary(
                id: currentUserId.uuidString,
                displayName: displayName,
                handle: handle,
                avatarInitials: initials
            )
            
            NotificationService.shared.createFollowNotification(
                from: fromUser,
                targetUserId: userId.uuidString
            )
        }
    }
    
    func unfollow(userId: UUID) async throws {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "FollowService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await supabase
            .from("user_follows")
            .delete()
            .eq("follower_id", value: currentUserId)
            .eq("followed_id", value: userId)
            .execute()
    }
    
    func isFollowing(userId: UUID) async throws -> Bool {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            return false
        }
        
        struct FollowRow: Codable {
            let follower_id: UUID
            let followed_id: UUID
        }
        
        let response: [FollowRow] = try await supabase
            .from("user_follows")
            .select("*")
            .eq("follower_id", value: currentUserId)
            .eq("followed_id", value: userId)
            .limit(1)
            .execute()
            .value
        
        return !response.isEmpty
    }
    
    func getFollowingCount(userId: UUID) async throws -> Int {
        struct FollowRow: Codable {
            let follower_id: UUID
            let followed_id: UUID
        }
        
        let response: [FollowRow] = try await supabase
            .from("user_follows")
            .select("*")
            .eq("follower_id", value: userId)
            .execute()
            .value
        
        return response.count
    }
    
    func getFollowersCount(userId: UUID) async throws -> Int {
        struct FollowRow: Codable {
            let follower_id: UUID
            let followed_id: UUID
        }
        
        let response: [FollowRow] = try await supabase
            .from("user_follows")
            .select("*")
            .eq("followed_id", value: userId)
            .execute()
            .value
        
        return response.count
    }
}

