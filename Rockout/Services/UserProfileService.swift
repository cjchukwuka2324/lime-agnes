import Foundation
import Supabase

@MainActor
class UserProfileService {
    static let shared = UserProfileService()
    
    private let supabase = SupabaseService.shared.client
    
    struct UserProfile: Codable {
        let id: UUID
        let displayName: String?
        let firstName: String?
        let lastName: String?
        let instagramHandle: String?
        let profilePictureURL: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case firstName = "first_name"
            case lastName = "last_name"
            case instagramHandle = "instagram_handle"
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
            .update(["instagram_handle": cleanHandle])
            .eq("id", value: userId)
            .execute()
    }
    
    func createOrUpdateProfile(firstName: String, lastName: String, displayName: String? = nil) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let displayNameValue = displayName ?? "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        try await supabase
            .from("profiles")
            .upsert([
                "id": userId.uuidString,
                "first_name": firstName,
                "last_name": lastName,
                "display_name": displayNameValue,
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
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
}

