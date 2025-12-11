import Foundation
import Supabase

/// Service for syncing contacts to the server and matching them with existing users
protocol ContactSyncService {
    func syncContacts(_ contacts: [Contact]) async throws -> [MatchedContact]
    func getMatchedContacts() async throws -> [MatchedContact]
}

struct MatchedContact: Identifiable, Hashable {
    let id: String
    let contactName: String
    let contactPhone: String?
    let contactEmail: String?
    let matchedUser: UserSummary?
    let hasAccount: Bool
}

final class SupabaseContactSyncService: ContactSyncService {
    static let shared = SupabaseContactSyncService()
    
    private let supabase = SupabaseService.shared.client
    
    func syncContacts(_ contacts: [Contact]) async throws -> [MatchedContact] {
        // Get current user ID
        guard let currentUserId = supabase.auth.currentUser?.id.uuidString else {
            throw NSError(domain: "ContactSyncService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Prepare contacts data for RPC call
        let contactsData: [[String: Any]] = contacts.map { contact in
            var data: [String: Any] = [
                "name": contact.displayName,
                "phone_numbers": contact.phoneNumbers
            ]
            return data
        }
        
        // Call RPC function to sync and match contacts
        // Convert contacts data to JSONB format
        let contactsJSON = try JSONSerialization.data(withJSONObject: contactsData)
        let contactsJSONString = String(data: contactsJSON, encoding: .utf8) ?? "[]"
        
        struct MatchContactsParams: Codable {
            let p_user_id: String
            let p_contacts: String // JSONB as string
        }
        
        let params = MatchContactsParams(
            p_user_id: currentUserId,
            p_contacts: contactsJSONString
        )
        
        let response = try await supabase
            .rpc("match_contacts_with_users", params: params)
            .execute()
        
        // Parse response
        struct MatchedContactResponse: Codable {
            let contact_name: String
            let contact_phone: String?
            let contact_email: String?
            let matched_user_id: String?
            let matched_user_display_name: String?
            let matched_user_handle: String?
            let matched_user_avatar_url: String?
            let has_account: Bool
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let matchedContacts = try decoder.decode([MatchedContactResponse].self, from: response.data)
        
        // Convert to MatchedContact objects
        return matchedContacts.map { response in
            let matchedUser: UserSummary? = response.has_account && response.matched_user_id != nil ? UserSummary(
                id: response.matched_user_id!,
                displayName: response.matched_user_display_name ?? "Unknown",
                handle: response.matched_user_handle ?? "",
                avatarInitials: (response.matched_user_display_name ?? "U").prefix(2).uppercased(),
                profilePictureURL: response.matched_user_avatar_url.flatMap { URL(string: $0) },
                isFollowing: false,
                region: nil,
                followersCount: 0,
                followingCount: 0
            ) : nil
            
            return MatchedContact(
                id: "\(response.contact_phone ?? "")-\(response.contact_email ?? "")",
                contactName: response.contact_name,
                contactPhone: response.contact_phone,
                contactEmail: response.contact_email,
                matchedUser: matchedUser,
                hasAccount: response.has_account
            )
        }
    }
    
    func getMatchedContacts() async throws -> [MatchedContact] {
        guard let currentUserId = supabase.auth.currentUser?.id.uuidString else {
            throw NSError(domain: "ContactSyncService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Query user_contacts table for matched contacts
        let response = try await supabase
            .from("user_contacts")
            .select("""
                contact_name,
                contact_phone,
                contact_email,
                matched_user_id,
                profiles!user_contacts_matched_user_id_fkey (
                    id,
                    display_name,
                    handle,
                    profile_picture_url
                )
            """)
            .eq("user_id", value: currentUserId)
            .execute()
        
        // Parse response and convert to MatchedContact
        // This is a simplified version - you may need to adjust based on actual response structure
        struct ContactRow: Codable {
            let contact_name: String
            let contact_phone: String?
            let contact_email: String?
            let matched_user_id: String?
            let profiles: ProfileData?
            
            struct ProfileData: Codable {
                let id: String
                let display_name: String
                let handle: String
                let profile_picture_url: String?
            }
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try decoder.decode([ContactRow].self, from: response.data)
        
        // Return ALL contacts, including those without accounts (matched_user_id == nil)
        // This allows us to show invite buttons for contacts without accounts
        return rows.map { row in
            let matchedUser: UserSummary? = row.profiles.map { profile in
                UserSummary(
                    id: profile.id,
                    displayName: profile.display_name,
                    handle: profile.handle,
                    avatarInitials: profile.display_name.prefix(2).uppercased(),
                    profilePictureURL: profile.profile_picture_url.flatMap { URL(string: $0) },
                    isFollowing: false,
                    region: nil,
                    followersCount: 0,
                    followingCount: 0
                )
            }
            
            return MatchedContact(
                id: "\(row.contact_phone ?? "")-\(row.contact_email ?? "")",
                contactName: row.contact_name,
                contactPhone: row.contact_phone,
                contactEmail: row.contact_email,
                matchedUser: matchedUser,
                hasAccount: row.matched_user_id != nil
            )
        }
    }
}


