import Foundation
import Supabase
import Combine

@MainActor
class UserProfileService: ObservableObject {
    static let shared = UserProfileService()
    
    private let supabase = SupabaseService.shared.client
    
    struct UserProfile: Codable {
        let id: UUID
        let displayName: String?
        let firstName: String?
        let lastName: String?
        let username: String?
        let instagramHandle: String?
        let twitterHandle: String?
        let tiktokHandle: String?
        let profilePictureURL: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case firstName = "first_name"
            case lastName = "last_name"
            case username
            case instagramHandle = "instagram"
            case twitterHandle = "twitter"
            case tiktokHandle = "tiktok"
            case profilePictureURL = "profile_picture_url"
        }
    }
    
    func getCurrentUserProfile() async throws -> UserProfile? {
        guard let userId = supabase.auth.currentUser?.id else {
            return nil
        }
        
        let response: [UserProfile] = try await supabase
            .from("profiles")
            .select("*")
            .eq("id", value: userId)
            .execute()
            .value
        
        return response.first
    }
    
    func updateInstagramHandle(_ handle: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Remove @ if present
        let cleanHandle = handle.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        
        try await supabase
            .from("profiles")
            .update(["instagram": cleanHandle])
            .eq("id", value: userId)
            .execute()
    }
    
    func checkUsernameAvailability(_ username: String) async throws -> Bool {
        let response: [UserProfile] = try await supabase
            .from("profiles")
            .select("username")
            .eq("username", value: username.lowercased())
            .execute()
            .value
        
        return response.isEmpty
    }
    
    func createOrUpdateProfile(firstName: String, lastName: String, username: String? = nil, displayName: String? = nil) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Check username availability if provided
        if let username = username {
            let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
            let isAvailable = try await checkUsernameAvailability(trimmedUsername)
            if !isAvailable {
                throw NSError(domain: "UserProfileService", code: 409, userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])
            }
        }
        
        let displayNameValue = displayName ?? "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        var profileData: [String: String] = [
            "id": userId.uuidString,
            "first_name": firstName,
            "last_name": lastName,
            "display_name": displayNameValue,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let username = username {
            profileData["username"] = username.trimmingCharacters(in: .whitespaces).lowercased()
        }
        
        try await supabase
            .from("profiles")
            .upsert(profileData)
            .execute()
    }
    
    func updateProfilePicture(_ imageURL: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await supabase
            .from("profiles")
            .update(["profile_picture_url": imageURL])
            .eq("id", value: userId)
            .execute()
    }
    
    func updateName(firstName: String, lastName: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let displayNameValue = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        try await supabase
            .from("profiles")
            .update([
                "first_name": firstName,
                "last_name": lastName,
                "display_name": displayNameValue,
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: userId)
            .execute()
    }
    
    func updateUsername(_ username: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Check username availability
        let isAvailable = try await checkUsernameAvailability(trimmedUsername)
        if !isAvailable {
            throw NSError(domain: "UserProfileService", code: 409, userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])
        }
        
        try await supabase
            .from("profiles")
            .update([
                "username": trimmedUsername,
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: userId)
            .execute()
    }
    
    func updateSocialMediaHandle(platform: SocialMediaPlatform, handle: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Remove @ if present
        let cleanHandle = handle.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        
        let columnName: String
        switch platform {
        case .instagram:
            columnName = "instagram"
        case .twitter:
            columnName = "twitter"
        case .tiktok:
            columnName = "tiktok"
        }
        
        try await supabase
            .from("profiles")
            .update([columnName: cleanHandle])
            .eq("id", value: userId)
            .execute()
    }
}

