import Foundation
import Supabase

final class ShareService {
    static let shared = ShareService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Create Share Link for Album
    func createShareLink(for albumId: UUID) async throws -> String {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Generate unique share token
        let shareToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        
        // Create shareable link
        struct ShareableLinkDTO: Encodable {
            let resource_type: String
            let resource_id: String
            let share_token: String
            let created_by: String
        }
        
        let linkDTO = ShareableLinkDTO(
            resource_type: "album",
            resource_id: albumId.uuidString,
            share_token: shareToken,
            created_by: userId
        )
        
        // Check if share link already exists
        do {
            struct ExistingLink: Codable {
                let share_token: String
            }
            
            let existing: ExistingLink = try await supabase
                .from("shareable_links")
                .select("share_token")
                .eq("resource_type", value: "album")
                .eq("resource_id", value: albumId.uuidString)
                .eq("created_by", value: userId)
                .eq("is_active", value: true)
                .single()
                .execute()
                .value
            
            return existing.share_token
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
    func acceptSharedAlbum(shareToken: String) async throws -> StudioAlbumRecord {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Find the shareable link
        struct ShareLink: Codable {
            let id: UUID
            let resource_id: UUID
            let created_by: UUID
        }
        
        struct AlbumCheck: Codable {
            let id: UUID
            let title: String
        }
        
        let shareLinkResponse = try await supabase
            .from("shareable_links")
            .select("id, resource_id, created_by")
            .eq("share_token", value: shareToken)
            .eq("is_active", value: true)
            .limit(1)
            .execute()
        
        let shareLinkArray = try JSONDecoder().decode([ShareLink].self, from: shareLinkResponse.data)
        
        guard let shareLink = shareLinkArray.first else {
            throw NSError(domain: "ShareService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Share link not found or expired"])
        }
        
        print("🔗 Found share link for album: \(shareLink.resource_id.uuidString)")
        
        // Verify the album exists before proceeding
        do {
            let albumCheck = try await supabase
                .from("albums")
                .select("id, title")
                .eq("id", value: shareLink.resource_id.uuidString)
                .limit(1)
                .execute()
            
            let albumCheckArray = try JSONDecoder().decode([AlbumCheck].self, from: albumCheck.data)
            if albumCheckArray.isEmpty {
                throw NSError(domain: "ShareService", code: 404, userInfo: [NSLocalizedDescriptionKey: "The shared album no longer exists. It may have been deleted."])
            }
            print("✅ Verified album exists: \(albumCheckArray.first?.title ?? "Unknown")")
        } catch {
            print("❌ Error verifying album exists: \(error)")
            throw error
        }
        
        // Check if already shared
        struct ExistingShare: Codable {
            let id: UUID
        }
        
        do {
            let existingResponse = try await supabase
                .from("shared_albums")
                .select("id")
                .eq("album_id", value: shareLink.resource_id.uuidString)
                .eq("shared_with", value: userId)
                .limit(1)
                .execute()
            
            let existingArray = try JSONDecoder().decode([ExistingShare].self, from: existingResponse.data)
            
            if let existing = existingArray.first {
                // Already shared, just fetch the album
                print("✅ Album already shared, fetching existing record")
                return try await fetchSharedAlbum(albumId: shareLink.resource_id)
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
        }
        
        let now = ISO8601DateFormatter().string(from: Date())
        let shareDTO = SharedAlbumDTO(
            album_id: shareLink.resource_id.uuidString,
            shared_by: shareLink.created_by.uuidString,
            shared_with: userId,
            share_token: shareToken,
            accepted_at: now
        )
        
        do {
            try await supabase
                .from("shared_albums")
                .insert(shareDTO)
                .execute()
            
            print("✅ Successfully created shared album record")
            return try await fetchSharedAlbum(albumId: shareLink.resource_id)
        } catch {
            // If insert fails due to unique constraint, it means the record was created
            // between our check and insert (race condition). Just fetch the album.
            let errorString = String(describing: error)
            if errorString.contains("23505") || 
               errorString.contains("duplicate key") || 
               errorString.contains("unique constraint") {
                print("⚠️ Duplicate key detected (race condition), fetching existing record")
                return try await fetchSharedAlbum(albumId: shareLink.resource_id)
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
                    .from("artists")
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
    func getShareURL(for shareToken: String) -> String {
        return "rockout://share/\(shareToken)"
    }
}

