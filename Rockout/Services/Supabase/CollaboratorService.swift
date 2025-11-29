import Foundation
import Supabase

final class CollaboratorService {
    static let shared = CollaboratorService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    struct Collaborator: Codable, Identifiable {
        let id: UUID
        let user_id: UUID
        let username: String?
        let display_name: String?
        let email: String?
        let is_collaboration: Bool
        let accepted_at: String?
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
                    let email: String?
                }
                
                let profileResponse = try await supabase
                    .from("profiles")
                    .select("id, username, display_name, email")
                    .eq("id", value: record.shared_with.uuidString)
                    .single()
                    .execute()
                
                let profile = try JSONDecoder().decode(ProfileResponse.self, from: profileResponse.data)
                
                // Clean up empty strings to nil
                let username = profile.username?.isEmpty == false ? profile.username : nil
                let displayName = profile.display_name?.isEmpty == false ? profile.display_name : nil
                let email = profile.email?.isEmpty == false ? profile.email : nil
                
                print("✅ Fetched profile for collaborator \(record.shared_with):")
                print("   - username: \(username ?? "nil")")
                print("   - display_name: \(displayName ?? "nil")")
                print("   - email: \(email ?? "nil")")
                
                let collaborator = Collaborator(
                    id: record.shared_with,
                    user_id: record.shared_with,
                    username: username,
                    display_name: displayName,
                    email: email,
                    is_collaboration: record.is_collaboration,
                    accepted_at: record.accepted_at
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
                    accepted_at: record.accepted_at
                )
                collaborators.append(collaborator)
            }
        }
        
        return collaborators
    }
}

