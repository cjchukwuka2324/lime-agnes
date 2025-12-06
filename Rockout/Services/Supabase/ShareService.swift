import Foundation
import Supabase

final class ShareService {
    static let shared = ShareService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Create Share Link for Album
    func createShareLink(for albumId: UUID, isCollaboration: Bool = false, expiresAt: Date? = nil) async throws -> String {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Generate unique share token
        let shareToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        
        // Format expiration date if provided
        let expiresAtString: String?
        if let expiresAt = expiresAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            expiresAtString = formatter.string(from: expiresAt)
        } else {
            expiresAtString = nil
        }
        
        // Create shareable link
        struct ShareableLinkDTO: Encodable {
            let resource_type: String
            let resource_id: String
            let share_token: String
            let created_by: String
            let is_collaboration: Bool
            let expires_at: String?
        }
        
        let linkDTO = ShareableLinkDTO(
            resource_type: "album",
            resource_id: albumId.uuidString,
            share_token: shareToken,
            created_by: userId,
            is_collaboration: isCollaboration,
            expires_at: expiresAtString
        )
        
        // Check if any share link already exists for this album
        struct ExistingLink: Codable {
            let id: UUID
            let share_token: String
            let is_collaboration: Bool?
        }
        
        do {
            // Check for existing link (regardless of collaboration setting)
            let existing: ExistingLink = try await supabase
                .from("shareable_links")
                .select("id, share_token, is_collaboration")
                .eq("resource_type", value: "album")
                .eq("resource_id", value: albumId.uuidString)
                .eq("created_by", value: userId)
                .eq("is_active", value: true)
                .single()
                .execute()
                .value
            
            // If collaboration setting matches, return existing token
            if (existing.is_collaboration ?? false) == isCollaboration {
                return existing.share_token
            }
            
            // Collaboration setting is different, update the existing link
            struct UpdateDTO: Encodable {
                let share_token: String
                let is_collaboration: Bool
                let expires_at: String?
            }
            
            let updateDTO = UpdateDTO(
                share_token: shareToken,
                is_collaboration: isCollaboration,
                expires_at: expiresAtString
            )
            
            try await supabase
                .from("shareable_links")
                .update(updateDTO)
                .eq("id", value: existing.id.uuidString)
                .execute()
            
            return shareToken
        } catch {
            // No existing link, create new one
            try await supabase
                .from("shareable_links")
                .insert(linkDTO)
                .execute()
            
            return shareToken
        }
    }
    
    // MARK: - Accept Shared Album
    func acceptSharedAlbum(shareToken: String) async throws -> (album: StudioAlbumRecord, isCollaboration: Bool) {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Find the shareable link
        struct ShareLink: Codable {
            let id: UUID
            let resource_id: UUID
            let created_by: UUID
            let is_collaboration: Bool?
            let expires_at: String?
        }
        
        struct AlbumCheck: Codable {
            let id: UUID
            let title: String
        }
        
        let shareLinkResponse = try await supabase
            .from("shareable_links")
            .select("id, resource_id, created_by, is_collaboration, expires_at")
            .eq("share_token", value: shareToken)
            .eq("is_active", value: true)
            .limit(1)
            .execute()
        
        let shareLinkArray = try JSONDecoder().decode([ShareLink].self, from: shareLinkResponse.data)
        
        guard let shareLink = shareLinkArray.first else {
            throw NSError(domain: "ShareService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Share link not found or expired"])
        }
        
        // Check if share link has expired
        if let expiresAtString = shareLink.expires_at {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let expiresAt = formatter.date(from: expiresAtString) {
                if expiresAt < Date() {
                    throw NSError(domain: "ShareService", code: 410, userInfo: [NSLocalizedDescriptionKey: "This share link has expired"])
                }
            }
        }
        
        print("🔗 Found share link for album: \(shareLink.resource_id.uuidString)")
        
        // Check if user is the owner of the album
        if shareLink.created_by.uuidString == userId {
            // User is the owner - check album ownership to confirm
            struct AlbumOwner: Codable {
                let artist_id: UUID
            }
            
            do {
                let ownerResponse = try await supabase
                    .from("albums")
                    .select("artist_id")
                    .eq("id", value: shareLink.resource_id.uuidString)
                    .limit(1)
                    .execute()
                
                let ownerArray = try JSONDecoder().decode([AlbumOwner].self, from: ownerResponse.data)
                if let albumOwner = ownerArray.first, albumOwner.artist_id.uuidString == userId {
                    throw NSError(domain: "ShareService", code: 403, userInfo: [NSLocalizedDescriptionKey: "OWNER_DETECTED"])
                }
            } catch let error as NSError {
                if error.domain == "ShareService" && error.code == 403 {
                    throw error // Re-throw owner error
                }
                // If we can't verify ownership, continue (might be RLS issue)
                print("⚠️ Could not verify album ownership: \(error.localizedDescription)")
            }
        }
        
        // Note: We don't check if the album exists here because RLS requires a shared_albums record
        // to exist before we can view the album. If the share link exists and is active, the album must exist.
        // We'll verify the album exists after creating the share record.
        
        // Check if already shared
        struct ExistingShare: Codable {
            let id: UUID
            let is_collaboration: Bool?
        }
        
        do {
            let existingResponse = try await supabase
                .from("shared_albums")
                .select("id, is_collaboration")
                .eq("album_id", value: shareLink.resource_id.uuidString)
                .eq("shared_with", value: userId)
                .limit(1)
                .execute()
            
            let existingArray = try JSONDecoder().decode([ExistingShare].self, from: existingResponse.data)
            
            if let existing = existingArray.first {
                // Already shared; if this new link is collaboration, ensure the existing record is upgraded
                var isCollaboration = existing.is_collaboration ?? false
                
                if !isCollaboration, (shareLink.is_collaboration ?? false) {
                    struct UpgradeDTO: Encodable {
                        let is_collaboration: Bool
                    }
                    let upgrade = UpgradeDTO(is_collaboration: true)
                    
                    do {
                        try await supabase
                            .from("shared_albums")
                            .update(upgrade)
                            .eq("id", value: existing.id.uuidString)
                            .execute()
                        isCollaboration = true
                        print("✅ Upgraded existing share to collaboration for user \(userId)")
                    } catch {
                        print("⚠️ Failed to upgrade existing share to collaboration: \(error.localizedDescription)")
                    }
                }
                
                // Fetch the album after ensuring correct collaboration status
                print("✅ Album already shared, fetching existing record")
                let album = try await fetchSharedAlbum(albumId: shareLink.resource_id)
                return (album, isCollaboration)
            }
        } catch {
            // If check fails, continue to try inserting (might be a new share)
            print("⚠️ Error checking for existing share: \(error.localizedDescription)")
        }
        
        // Not shared yet, create share record
        struct SharedAlbumDTO: Encodable {
            let album_id: String
            let shared_by: String
            let shared_with: String
            let share_token: String
            let accepted_at: String
            let is_collaboration: Bool
        }
        
        let now = ISO8601DateFormatter().string(from: Date())
        let shareDTO = SharedAlbumDTO(
            album_id: shareLink.resource_id.uuidString,
            shared_by: shareLink.created_by.uuidString,
            shared_with: userId,
            share_token: shareToken,
            accepted_at: now,
            is_collaboration: shareLink.is_collaboration ?? false
        )
        
        do {
            try await supabase
                .from("shared_albums")
                .insert(shareDTO)
                .execute()
            
            print("✅ Successfully created shared album record")
            let album = try await fetchSharedAlbum(albumId: shareLink.resource_id)
            let isCollaboration = shareLink.is_collaboration ?? false
            return (album, isCollaboration)
        } catch {
            // If insert fails due to unique constraint, it means the record was created
            // between our check and insert (race condition). Just fetch the album.
            let errorString = String(describing: error)
            if errorString.contains("23505") || 
               errorString.contains("duplicate key") || 
               errorString.contains("unique constraint") {
                print("⚠️ Duplicate key detected (race condition), fetching existing record")
                let album = try await fetchSharedAlbum(albumId: shareLink.resource_id)
                let isCollaboration = shareLink.is_collaboration ?? false
                return (album, isCollaboration)
            }
            // Re-throw other errors
            print("❌ Error inserting shared album: \(error)")
            throw error
        }
    }
    
    // MARK: - Fetch Shared Album
    private func fetchSharedAlbum(albumId: UUID) async throws -> StudioAlbumRecord {
        print("🔍 Fetching album with ID: \(albumId.uuidString)")
        
        do {
            // Fetch album with artist name
            let response = try await supabase
                .from("albums")
                .select()
                .eq("id", value: albumId.uuidString)
                .limit(1)
                .execute()
            
            print("📦 Response data length: \(response.data.count) bytes")
            
            // Check if response is empty
            if response.data.isEmpty {
                throw NSError(domain: "ShareService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Album not found. It may have been deleted."])
            }
            
            let albumArray = try JSONDecoder().decode([StudioAlbumRecord].self, from: response.data)
            
            print("📋 Decoded \(albumArray.count) album(s)")
            
            guard var album = albumArray.first else {
                // Try to see what we got back
                if let responseString = String(data: response.data, encoding: .utf8) {
                    print("⚠️ Response was: \(responseString)")
                }
                throw NSError(domain: "ShareService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Album \(albumId.uuidString) not found in database"])
            }
            
            print("✅ Successfully fetched album: \(album.title)")
            
            // Fetch artist name
            do {
                struct ArtistResponse: Codable {
                    let name: String
                }
                
                let artistResponse = try await supabase
                    .from("studio_artists")
                    .select("name")
                    .eq("id", value: album.artist_id.uuidString)
                    .limit(1)
                    .execute()
                
                let artistArray = try JSONDecoder().decode([ArtistResponse].self, from: artistResponse.data)
                if let artist = artistArray.first {
                    album.artist_name = artist.name
                    print("✅ Fetched artist name: \(artist.name)")
                }
            } catch {
                print("⚠️ Failed to fetch artist name: \(error.localizedDescription)")
            }
            
            return album
        } catch let error as NSError where error.domain == "ShareService" {
            // Re-throw our custom errors
            throw error
        } catch {
            // Wrap other errors with more context
            print("❌ Error fetching album: \(error)")
            throw NSError(domain: "ShareService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch album: \(error.localizedDescription)"])
        }
    }
    
    // MARK: - Get Share URL
    /// Returns a deep link URL for a given share token.
    /// - Parameters:
    ///   - shareToken: The opaque token that identifies this share link.
    ///   - isCollaboration: Whether the link is for collaboration or view-only.
    ///   - Note: We keep the token opaque for security; the path prefix indicates intent.
    func getShareURL(for shareToken: String, isCollaboration: Bool) -> String {
        let pathPrefix = isCollaboration ? "collaborate" : "view"
        return "rockout://\(pathPrefix)/\(shareToken)"
    }

    // MARK: - Share Metadata
    /// Returns whether a given share token represents a collaboration invite.
    /// Returns nil if the token is invalid or not found.
    func isCollaborationInvite(shareToken: String) async throws -> Bool? {
        struct ShareLinkMeta: Codable {
            let is_collaboration: Bool?
        }
        
        do {
            let response = try await supabase
                .from("shareable_links")
                .select("is_collaboration")
                .eq("share_token", value: shareToken)
                .eq("is_active", value: true)
                .limit(1)
                .execute()
            
            let array = try JSONDecoder().decode([ShareLinkMeta].self, from: response.data)
            guard let meta = array.first else {
                return nil
            }
            return meta.is_collaboration ?? false
        } catch {
            print("⚠️ Failed to fetch share metadata: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Revoke Share Link
    /// Revokes a share link entirely by setting is_active to false and removing all shared_albums records
    func revokeShareLink(shareToken: String) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Verify the user owns this share link and get album ID
        struct ShareLinkInfo: Codable {
            let created_by: UUID
            let resource_id: UUID
        }
        
        let ownerResponse = try await supabase
            .from("shareable_links")
            .select("created_by, resource_id")
            .eq("share_token", value: shareToken)
            .single()
            .execute()
        
        let linkInfo = try JSONDecoder().decode(ShareLinkInfo.self, from: ownerResponse.data)
        
        guard linkInfo.created_by.uuidString == userId else {
            throw NSError(domain: "ShareService", code: 403, userInfo: [NSLocalizedDescriptionKey: "You don't have permission to revoke this share link"])
        }
        
        // First, delete all shared_albums records for this album where current user is the owner
        try await supabase
            .from("shared_albums")
            .delete()
            .eq("album_id", value: linkInfo.resource_id.uuidString)
            .eq("shared_by", value: userId)
            .execute()
        
        // Then, revoke the share link
        struct RevokeDTO: Encodable {
            let is_active: Bool
        }
        
        try await supabase
            .from("shareable_links")
            .update(RevokeDTO(is_active: false))
            .eq("share_token", value: shareToken)
            .execute()
    }
    
    // MARK: - Revoke Access for Specific User
    /// Revokes access for a specific user by removing their shared_albums record
    func revokeAccessForUser(albumId: UUID, userIdToRevoke: UUID) async throws {
        let session = try await supabase.auth.session
        let currentUserId = session.user.id.uuidString
        
        // Verify the current user owns this album
        struct AlbumOwner: Codable {
            let artist_id: UUID
        }
        
        let albumResponse = try await supabase
            .from("albums")
            .select("artist_id")
            .eq("id", value: albumId.uuidString)
            .single()
            .execute()
        
        let album = try JSONDecoder().decode(AlbumOwner.self, from: albumResponse.data)
        
        guard album.artist_id.uuidString == currentUserId else {
            throw NSError(domain: "ShareService", code: 403, userInfo: [NSLocalizedDescriptionKey: "You don't have permission to revoke access for this album"])
        }
        
        // Delete the shared_albums record for this specific user
        try await supabase
            .from("shared_albums")
            .delete()
            .eq("album_id", value: albumId.uuidString)
            .eq("shared_with", value: userIdToRevoke.uuidString)
            .eq("shared_by", value: currentUserId)
            .execute()
    }
    
    // MARK: - Get All Users With Access
    /// Fetches all users who have access to an album (both collaborators and view-only)
    func getAllUsersWithAccess(for albumId: UUID) async throws -> [CollaboratorService.Collaborator] {
        return try await CollaboratorService.shared.fetchCollaborators(for: albumId)
    }
    
    // MARK: - Get Share Link Details
    /// Fetches share link details for a given album
    func getShareLinkDetails(for albumId: UUID) async throws -> ShareableLink? {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        let response = try await supabase
            .from("shareable_links")
            .select()
            .eq("resource_type", value: "album")
            .eq("resource_id", value: albumId.uuidString)
            .eq("created_by", value: userId)
            .eq("is_active", value: true)
            .limit(1)
            .execute()
        
        let links = try JSONDecoder().decode([ShareableLink].self, from: response.data)
        return links.first
    }
}

