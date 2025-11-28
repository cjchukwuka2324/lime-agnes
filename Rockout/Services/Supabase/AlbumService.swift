import Foundation
import Supabase

final class AlbumService {
    static let shared = AlbumService()
    private init() {}

    private let supabase = SupabaseService.shared.client

    struct CreateAlbumDTO: Encodable {
        let title: String
        let artist_id: String
        let release_status: String
        let cover_art_url: String?
    }

    // MARK: - CREATE ALBUM (WITH COVER ART)
    func createAlbum(title: String, artistName: String?, coverArtData: Data?) async throws -> StudioAlbumRecord {

        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString

        // Ensure artist record exists for this user, with optional custom name
        let artistId = try await ensureArtistExists(userId: userId, customName: artistName)

        // Upload cover art if provided
        var coverArtUrl: String? = nil

        if let data = coverArtData {
            let filename = "\(UUID().uuidString).jpg"
            let path = filename

            do {
                print("📤 Uploading cover art to album-cover-art bucket, path: \(path)")
                try await supabase.storage
                    .from("album-cover-art")
                    .upload(path: path, file: data)
                print("✅ Cover art uploaded successfully")
                
                coverArtUrl = try supabase.storage
                    .from("album-cover-art")
                    .getPublicURL(path: path)
                    .absoluteString
                print("✅ Got public URL: \(coverArtUrl ?? "nil")")
            } catch {
                print("❌ Error uploading cover art: \(error.localizedDescription)")
                // Don't fail the entire album creation if cover art upload fails
                // Just log it and continue without cover art
                print("⚠️ Continuing album creation without cover art")
            }
        }

        let dto = CreateAlbumDTO(
            title: title,
            artist_id: artistId,
            release_status: "draft",
            cover_art_url: coverArtUrl
        )

        print("📝 Creating album with title: \(title), artist_id: \(artistId), cover_art_url: \(coverArtUrl != nil ? "set" : "nil")")
        
        do {
            let response = try await supabase
                .from("albums")
                .insert(dto)
                .select()
                .single()
                .execute()
            
            print("✅ Album created successfully")
            return try JSONDecoder().decode(StudioAlbumRecord.self, from: response.data)
        } catch {
            print("❌ Error creating album: \(error.localizedDescription)")
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("row-level security") || errorString.contains("rls") {
                print("🔒 RLS Error - This might be a storage or database RLS policy issue")
                print("   Album data: title=\(title), artist_id=\(artistId), has_cover_art=\(coverArtUrl != nil)")
            }
            throw error
        }
    }
    
    // MARK: - Ensure Artist Exists
    private func ensureArtistExists(userId: String, customName: String? = nil) async throws -> String {
        let session = try await supabase.auth.session
        let user = session.user
        
        // Use custom name if provided, otherwise get from profile or metadata
        var artistName: String
        
        if let customName = customName, !customName.trimmingCharacters(in: .whitespaces).isEmpty {
            artistName = customName.trimmingCharacters(in: .whitespaces)
        } else {
            // Get user's name from profile or metadata
            artistName = user.email ?? "Unknown Artist"
            
            // Try to get name from user_profiles
            do {
                struct ProfileResponse: Codable {
                    let first_name: String?
                    let last_name: String?
                    let full_name: String?
                }
                
                let profileResponse: ProfileResponse = try await supabase
                    .database
                    .from("user_profiles")
                    .select("first_name, last_name, full_name")
                    .eq("id", value: userId)
                    .single()
                    .execute()
                    .value
                
                if let fullName = profileResponse.full_name, !fullName.isEmpty {
                    artistName = fullName
                } else if let firstName = profileResponse.first_name,
                          let lastName = profileResponse.last_name,
                          !firstName.isEmpty, !lastName.isEmpty {
                    artistName = "\(firstName) \(lastName)"
                }
            } catch {
                // Try metadata as fallback
                let userMetadata = user.userMetadata
                if let firstNameJSON = userMetadata["first_name"],
                   let lastNameJSON = userMetadata["last_name"] {
                    var firstName: String?
                    var lastName: String?
                    
                    switch firstNameJSON {
                    case .string(let value): firstName = value
                    default: break
                    }
                    
                    switch lastNameJSON {
                    case .string(let value): lastName = value
                    default: break
                    }
                    
                    if let firstName = firstName, let lastName = lastName,
                       !firstName.isEmpty, !lastName.isEmpty {
                        artistName = "\(firstName) \(lastName)"
                    }
                }
            }
        }
        
        // Create or update artist record (id is both primary key and user reference)
        struct ArtistData: Encodable {
            let id: String
            let name: String
            let created_at: String?
            let updated_at: String?
        }
        
        let now = ISO8601DateFormatter().string(from: Date())
        let artistData = ArtistData(
            id: userId,
            name: artistName,
            created_at: now,
            updated_at: now
        )
        
        // Try to insert artist record into studio_artists table
        // If it fails due to duplicate, update the existing record with the new name
        do {
            try await supabase
                .from("studio_artists")
                .insert(artistData)
                .execute()
            
            print("✅ Created studio artist record: \(artistName)")
        } catch {
            // Check if error is due to duplicate key (artist already exists)
            let errorString = error.localizedDescription.lowercased()
            if errorString.contains("duplicate") || 
               errorString.contains("unique") || 
               errorString.contains("already exists") {
                // Artist exists, update the name if custom name was provided
                if customName != nil {
                    try await supabase
                        .from("studio_artists")
                        .update(["name": artistName, "updated_at": now])
                        .eq("id", value: userId)
                        .execute()
                    print("✅ Updated studio artist name: \(artistName)")
                } else {
                    print("ℹ️ Studio artist record already exists")
                }
            } else {
                // Re-throw if it's a different error (like table doesn't exist)
                print("⚠️ Error creating studio artist: \(error.localizedDescription)")
                // Don't throw - allow album creation to proceed
                // The foreign key constraint will handle validation
            }
        }
        
        return userId
    }

    // MARK: - FETCH ALBUMS (NAME RESTORED)
    func fetchMyAlbums() async throws -> [StudioAlbumRecord] {

        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString

        // Fetch albums and then fetch artist names separately
        let response = try await supabase
            .from("albums")
            .select()
            .eq("artist_id", value: userId)
            .order("created_at", ascending: false)
            .execute()

        var albums = try JSONDecoder().decode([StudioAlbumRecord].self, from: response.data)
        
        // Fetch artist names for all unique artist_ids
        let uniqueArtistIds = Set(albums.map { $0.artist_id })
        var artistNames: [UUID: String] = [:]
        
        for artistId in uniqueArtistIds {
            do {
                struct ArtistResponse: Codable {
                    let name: String
                }
                
                let artistResponse: ArtistResponse = try await supabase
                    .from("studio_artists")
                    .select("name")
                    .eq("id", value: artistId.uuidString)
                    .single()
                    .execute()
                    .value
                
                artistNames[artistId] = artistResponse.name
            } catch {
                print("⚠️ Failed to fetch artist name for \(artistId): \(error.localizedDescription)")
            }
        }
        
        // Update albums with artist names
        return albums.map { album in
            var updatedAlbum = album
            updatedAlbum.artist_name = artistNames[album.artist_id]
            return updatedAlbum
        }
    }

    // MARK: - FETCH SHARED ALBUMS
    func fetchSharedAlbums() async throws -> [StudioAlbumRecord] {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Fetch shared albums
        struct SharedAlbumResponse: Codable {
            let album_id: UUID
            let shared_by: UUID
            let created_at: String?
        }
        
        let sharedResponse = try await supabase
            .from("shared_albums")
            .select("album_id, shared_by, created_at")
            .eq("shared_with", value: userId)
            .eq("is_collaboration", value: false)
            .order("created_at", ascending: false)
            .execute()
        
        let sharedAlbums = try JSONDecoder().decode([SharedAlbumResponse].self, from: sharedResponse.data)
        
        guard !sharedAlbums.isEmpty else {
            return []
        }
        
        // Fetch album details for each shared album
        var albums: [StudioAlbumRecord] = []
        
        for sharedAlbum in sharedAlbums {
            do {
                // Fetch album - use limit(1) and check if empty
                let albumResponse = try await supabase
                    .from("albums")
                    .select()
                    .eq("id", value: sharedAlbum.album_id.uuidString)
                    .limit(1)
                    .execute()
                
                let albumArray = try JSONDecoder().decode([StudioAlbumRecord].self, from: albumResponse.data)
                
                guard let albumData = albumArray.first else {
                    print("⚠️ Album \(sharedAlbum.album_id) not found, skipping")
                    continue
                }
                
                var album = albumData
                
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
                    }
                } catch {
                    print("⚠️ Failed to fetch artist name for album \(sharedAlbum.album_id): \(error.localizedDescription)")
                }
                
                albums.append(album)
            } catch {
                print("⚠️ Failed to fetch shared album \(sharedAlbum.album_id): \(error.localizedDescription)")
            }
        }
        
        return albums
    }

    // MARK: - FETCH COLLABORATIVE ALBUMS
    func fetchCollaborativeAlbums() async throws -> [StudioAlbumRecord] {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Fetch collaborative albums (where is_collaboration = true)
        struct SharedAlbumResponse: Codable {
            let album_id: UUID
            let shared_by: UUID
            let created_at: String?
        }
        
        let sharedResponse = try await supabase
            .from("shared_albums")
            .select("album_id, shared_by, created_at")
            .eq("shared_with", value: userId)
            .eq("is_collaboration", value: true)
            .order("created_at", ascending: false)
            .execute()
        
        let sharedAlbums = try JSONDecoder().decode([SharedAlbumResponse].self, from: sharedResponse.data)
        
        guard !sharedAlbums.isEmpty else {
            return []
        }
        
        // Fetch album details for each collaborative album
        var albums: [StudioAlbumRecord] = []
        
        for sharedAlbum in sharedAlbums {
            do {
                // Fetch album - use limit(1) and check if empty
                let albumResponse = try await supabase
                    .from("albums")
                    .select()
                    .eq("id", value: sharedAlbum.album_id.uuidString)
                    .limit(1)
                    .execute()
                
                let albumArray = try JSONDecoder().decode([StudioAlbumRecord].self, from: albumResponse.data)
                
                guard let albumData = albumArray.first else {
                    print("⚠️ Album \(sharedAlbum.album_id) not found, skipping")
                    continue
                }
                
                var album = albumData
                
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
                    }
                } catch {
                    print("⚠️ Failed to fetch artist name for album \(sharedAlbum.album_id): \(error.localizedDescription)")
                }
                
                albums.append(album)
            } catch {
                print("⚠️ Failed to fetch collaborative album \(sharedAlbum.album_id): \(error.localizedDescription)")
            }
        }
        
        return albums
    }

    // MARK: - UPDATE ALBUM
    func updateAlbum(
        _ album: StudioAlbumRecord,
        title: String?,
        artistName: String?,
        coverArtData: Data?
    ) async throws -> StudioAlbumRecord {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Verify album ownership before updating
        struct AlbumCheck: Codable {
            let id: UUID
            let artist_id: UUID
        }
        
        let checkResponse = try await supabase
            .from("albums")
            .select("id, artist_id")
            .eq("id", value: album.id.uuidString)
            .single()
            .execute()
        
        let albumCheck = try JSONDecoder().decode(AlbumCheck.self, from: checkResponse.data)
        
        // Verify ownership
        guard albumCheck.artist_id.uuidString == userId else {
            throw NSError(
                domain: "AlbumService",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "You don't have permission to update this album"]
            )
        }
        
        // Upload cover art if provided
        var coverArtUrl: String? = nil
        if let coverArtData = coverArtData {
            let filename = "\(UUID().uuidString).jpg"
            let path = filename
            
            try await supabase.storage
                .from("album-cover-art")
                .upload(path: path, file: coverArtData, options: FileOptions(upsert: true))
            
            coverArtUrl = try supabase.storage
                .from("album-cover-art")
                .getPublicURL(path: path)
                .absoluteString
        }
        
        // Update album in database if there are changes
        // Only update fields that are provided (non-nil)
        if title != nil || coverArtUrl != nil {
            struct UpdateDTO: Encodable {
                let title: String?
                let cover_art_url: String?
            }
            
            let updateDTO = UpdateDTO(
                title: title?.trimmingCharacters(in: .whitespaces).isEmpty == false ? title?.trimmingCharacters(in: .whitespaces) : nil,
                cover_art_url: coverArtUrl
            )
            
            print("🔄 Updating album \(album.id.uuidString) with title: \(title ?? "nil"), coverArtUrl: \(coverArtUrl != nil ? "set" : "nil")")
            
            try await supabase
                .from("albums")
                .update(updateDTO)
                .eq("id", value: album.id.uuidString)
                .execute()
            
            print("✅ Album updated successfully")
        }
        
        // Update artist name if provided
        if let artistName = artistName, !artistName.trimmingCharacters(in: .whitespaces).isEmpty {
            let session = try await supabase.auth.session
            let userId = session.user.id.uuidString
            
            // Ensure artist record exists first
            do {
                try await ensureArtistExists(userId: userId, customName: artistName.trimmingCharacters(in: .whitespaces))
                print("✅ Updated studio artist name: \(artistName)")
            } catch {
                print("⚠️ Error updating studio artist name: \(error.localizedDescription)")
                // Don't throw - allow album update to succeed even if artist name update fails
            }
        }
        
        // Fetch and return updated album
        let response = try await supabase
            .from("albums")
            .select()
            .eq("id", value: album.id.uuidString)
            .single()
            .execute()
        
        var updatedAlbum = try JSONDecoder().decode(StudioAlbumRecord.self, from: response.data)
        
        // Fetch artist name
        do {
            struct ArtistResponse: Codable {
                let name: String
            }
            
            let artistResponse = try await supabase
                .from("studio_artists")
                .select("name")
                .eq("id", value: updatedAlbum.artist_id.uuidString)
                .single()
                .execute()
            
            updatedAlbum.artist_name = try JSONDecoder().decode(ArtistResponse.self, from: artistResponse.data).name
        } catch {
            print("⚠️ Failed to fetch artist name: \(error.localizedDescription)")
        }
        
        return updatedAlbum
    }

    // MARK: - DELETE ALBUM
    func deleteAlbum(_ album: StudioAlbumRecord) async throws {
        try await supabase
            .from("albums")
            .delete()
            .eq("id", value: album.id.uuidString)
            .execute()
    }
}

