import Foundation
import Supabase

final class CollaboratorService {
    static let shared = CollaboratorService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    struct Collaborator: Identifiable {
        let id: UUID
        let user_id: UUID
        let username: String?
        let display_name: String?
        let email: String?
        let is_collaboration: Bool
        let accepted_at: String?
        let profilePictureURL: URL?
    }
    
    // MARK: - Fetch Collaborators for Album
    func fetchCollaborators(for albumId: UUID) async throws -> [Collaborator] {
        let session = try await supabase.auth.session
        let currentUserId = session.user.id.uuidString
        
        // Fetch shared_albums records for this album (exclude current user, only accepted shares)
        struct SharedAlbumRecord: Codable {
            let shared_with: UUID
            let is_collaboration: Bool
            let accepted_at: String?
        }
        
        let sharedResponse = try await supabase
            .from("shared_albums")
            .select("shared_with, is_collaboration, accepted_at")
            .eq("album_id", value: albumId.uuidString)
            .neq("shared_with", value: currentUserId) // Exclude current user
            .execute()
        
        let allSharedRecords = try JSONDecoder().decode([SharedAlbumRecord].self, from: sharedResponse.data)
        
        // Filter to only accepted shares (accepted_at is not null)
        let sharedRecords = allSharedRecords.filter { $0.accepted_at != nil }
        
        // Fetch user profiles for each collaborator
        var collaborators: [Collaborator] = []
        
        for record in sharedRecords {
            do {
                struct ProfileResponse: Codable {
                    let id: UUID
                    let username: String?
                    let display_name: String?
                    let first_name: String?
                    let last_name: String?
                    let profile_picture_url: String?
                }
                
                let profileResponse = try await supabase
                    .from("profiles")
                    .select("id, username, display_name, first_name, last_name, profile_picture_url")
                    .eq("id", value: record.shared_with.uuidString)
                    .single()
                    .execute()
                
                let profile = try JSONDecoder().decode(ProfileResponse.self, from: profileResponse.data)
                
                // Clean up empty strings to nil
                let username = profile.username?.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanUsername = username?.isEmpty == false ? username : nil
                
                let rawDisplay = profile.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
                let first = profile.first_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let last = profile.last_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let combinedName = "\(first) \(last)".trimmingCharacters(in: .whitespacesAndNewlines)
                
                let cleanDisplayName: String?
                if let raw = rawDisplay, !raw.isEmpty {
                    cleanDisplayName = raw
                } else if !combinedName.isEmpty {
                    cleanDisplayName = combinedName
                } else {
                    cleanDisplayName = nil
                }
                
                // We don't have email on profiles in this schema
                let cleanEmail: String? = nil
                
                // Convert profile picture URL string to URL
                let profilePictureURL: URL? = profile.profile_picture_url.flatMap { URL(string: $0) }
                
                print("✅ Fetched profile for collaborator \(record.shared_with):")
                print("   - username: \(cleanUsername ?? "nil")")
                print("   - display_name: \(cleanDisplayName ?? "nil")")
                print("   - profile_picture_url: \(profilePictureURL?.absoluteString ?? "nil")")
                
                let collaborator = Collaborator(
                    id: record.shared_with,
                    user_id: record.shared_with,
                    username: cleanUsername,
                    display_name: cleanDisplayName,
                    email: cleanEmail,
                    is_collaboration: record.is_collaboration,
                    accepted_at: record.accepted_at,
                    profilePictureURL: profilePictureURL
                )
                
                collaborators.append(collaborator)
            } catch {
                print("⚠️ Failed to fetch profile for collaborator \(record.shared_with): \(error.localizedDescription)")
                print("⚠️ Error details: \(error)")
                // Add collaborator with minimal info
                let collaborator = Collaborator(
                    id: record.shared_with,
                    user_id: record.shared_with,
                    username: nil,
                    display_name: nil,
                    email: nil,
                    is_collaboration: record.is_collaboration,
                    accepted_at: record.accepted_at,
                    profilePictureURL: nil
                )
                collaborators.append(collaborator)
            }
        }
        
        return collaborators
    }
}

