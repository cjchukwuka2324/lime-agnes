import Foundation
import Supabase

protocol SuggestedFollowService {
    func loadSuggestions(contactService: ContactsService) async throws -> [UserSummary]
}

final class SupabaseSuggestedFollowService: SuggestedFollowService {
    private let supabase = SupabaseService.shared.client
    private let social = SupabaseSocialGraphService.shared
    
    func loadSuggestions(contactService: ContactsService) async throws -> [UserSummary] {
        // Request contacts permission and fetch contacts
        guard await contactService.requestPermission() else {
            return [] // Return empty if permission denied
        }
        
        let contacts = try await contactService.fetchContacts()
        
        // Extract all phone numbers from contacts
        let phoneNumbers = Set(contacts.flatMap { $0.phoneNumbers })
        
        if phoneNumbers.isEmpty {
            return []
        }
        
        // Get current user ID
        guard let currentUserId = supabase.auth.currentUser?.id.uuidString else {
            throw NSError(domain: "SuggestedFollowService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Get users already followed by current user
        let followingIds = await social.followingIds()
        
        // Query profiles matching phone numbers
        // Note: This assumes profiles table has a 'phone' or 'phone_hash' column
        // You may need to adjust the query based on your actual schema
        var matchingProfiles: [UserSummary] = []
        
        // Query profiles in batches (Supabase has limits on IN clause size)
        let phoneArray = Array(phoneNumbers)
        let batchSize = 100
        
        for i in stride(from: 0, to: phoneArray.count, by: batchSize) {
            let batch = Array(phoneArray[i..<min(i + batchSize, phoneArray.count)])
            
            // Try to match by phone number (normalized)
            // Adjust this query based on your actual phone column name
            let response = try await supabase
                .from("profiles")
                .select("""
                    id,
                    display_name,
                    first_name,
                    last_name,
                    username,
                    profile_picture_url,
                    region,
                    followers_count,
                    following_count,
                    phone
                """)
                .in("phone", values: batch)
                .execute()
            
            struct ProfileRow: Decodable {
                let id: UUID
                let display_name: String?
                let first_name: String?
                let last_name: String?
                let username: String?
                let profile_picture_url: String?
                let region: String?
                let followers_count: Int?
                let following_count: Int?
                let phone: String?
            }
            
            let profiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: response.data)
            
            // Convert to UserSummary and filter out already followed users
            for profile in profiles {
                let profileId = profile.id.uuidString
                
                // Skip if already following
                if followingIds.contains(profileId) {
                    continue
                }
                
                // Skip current user
                if profileId == currentUserId {
                    continue
                }
                
                // Build display name
                let displayName: String
                if let firstName = profile.first_name, let lastName = profile.last_name {
                    displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                } else if let displayNameValue = profile.display_name, !displayNameValue.isEmpty {
                    displayName = displayNameValue
                } else if let username = profile.username {
                    displayName = username.capitalized
                } else {
                    displayName = "User"
                }
                
                // Build handle
                let handle = profile.username.map { "@\($0)" } ?? "@user"
                
                // Build initials
                let initials: String
                if let firstName = profile.first_name, let lastName = profile.last_name {
                    initials = "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
                } else if let displayNameValue = profile.display_name, displayNameValue.count >= 2 {
                    initials = String(displayNameValue.prefix(2)).uppercased()
                } else if let username = profile.username, username.count >= 2 {
                    initials = String(username.prefix(2)).uppercased()
                } else {
                    initials = "U"
                }
                
                // Build profile picture URL
                let profilePictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
                
                let userSummary = UserSummary(
                    id: profileId,
                    displayName: displayName,
                    handle: handle,
                    avatarInitials: initials,
                    profilePictureURL: profilePictureURL,
                    isFollowing: false,
                    region: profile.region,
                    followersCount: profile.followers_count ?? 0,
                    followingCount: profile.following_count ?? 0
                )
                
                matchingProfiles.append(userSummary)
            }
        }
        
        return matchingProfiles
    }
}
