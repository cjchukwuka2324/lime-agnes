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
        let artist_name: String?
        let is_public: Bool?
    }

    // MARK: - CREATE ALBUM (WITH COVER ART)
    func createAlbum(title: String, artistName: String?, coverArtData: Data?, isPublic: Bool = false) async throws -> StudioAlbumRecord {

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

        // Get artist name for this album (use custom name if provided, otherwise fetch from studio_artists)
        var albumArtistName: String? = nil
        if let customName = artistName, !customName.trimmingCharacters(in: .whitespaces).isEmpty {
            albumArtistName = customName.trimmingCharacters(in: .whitespaces)
        } else {
            // Fetch from studio_artists as fallback
            do {
                struct ArtistResponse: Codable {
                    let name: String
                }
                let artistResponse: ArtistResponse = try await supabase
                    .from("studio_artists")
                    .select("name")
                    .eq("id", value: artistId)
                    .single()
                    .execute()
                    .value
                albumArtistName = artistResponse.name
            } catch {
                print("⚠️ Could not fetch artist name: \(error.localizedDescription)")
            }
        }
        
        let dto = CreateAlbumDTO(
            title: title,
            artist_id: artistId,
            release_status: "draft",
            cover_art_url: coverArtUrl,
            artist_name: albumArtistName,
            is_public: isPublic
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
        
        // Fetch artist names from studio_artists only for albums that don't have artist_name set
        let albumsNeedingArtistName = albums.filter { $0.artist_name == nil || $0.artist_name?.isEmpty == true }
        let uniqueArtistIds = Set(albumsNeedingArtistName.map { $0.artist_id })
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
        
        // Fetch collaborator and viewer counts for all albums
        var collaboratorCounts: [UUID: Int] = [:]
        var viewerCounts: [UUID: Int] = [:]
        for album in albums {
            do {
                // Fetch shared_albums records with is_collaboration flag
                struct ShareRecord: Codable {
                    let id: UUID
                    let is_collaboration: Bool
                }
                
                let sharedResponse = try await supabase
                    .from("shared_albums")
                    .select("id, is_collaboration")
                    .eq("album_id", value: album.id.uuidString)
                    .execute()
                
                let shareRecords = try JSONDecoder().decode([ShareRecord].self, from: sharedResponse.data)
                
                // Count collaborators and viewers separately
                let collaborators = shareRecords.filter { $0.is_collaboration == true }
                let viewers = shareRecords.filter { $0.is_collaboration == false }
                
                collaboratorCounts[album.id] = collaborators.count
                viewerCounts[album.id] = viewers.count
            } catch {
                print("⚠️ Failed to fetch share counts for \(album.id): \(error.localizedDescription)")
                collaboratorCounts[album.id] = 0
                viewerCounts[album.id] = 0
            }
        }
        
        // Update albums with artist names (use album's artist_name if available, otherwise fall back to studio_artists)
        // and collaborator/viewer counts
        return albums.map { album in
            var updatedAlbum = album
            // Only set artist_name from studio_artists if album doesn't already have one
            if updatedAlbum.artist_name == nil || updatedAlbum.artist_name?.isEmpty == true {
                updatedAlbum.artist_name = artistNames[album.artist_id]
            }
            updatedAlbum.collaborator_count = collaboratorCounts[album.id] ?? 0
            updatedAlbum.viewer_count = viewerCounts[album.id] ?? 0
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
                
                // Fetch artist name from studio_artists only if album doesn't have one
                if album.artist_name == nil || album.artist_name?.isEmpty == true {
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
                
                // Fetch artist name from studio_artists only if album doesn't have one
                if album.artist_name == nil || album.artist_name?.isEmpty == true {
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
                }
                
                albums.append(album)
            } catch {
                print("⚠️ Failed to fetch collaborative album \(sharedAlbum.album_id): \(error.localizedDescription)")
            }
        }
        
        return albums
    }

    // MARK: - FETCH SINGLE ALBUM
    func fetchAlbum(albumId: UUID) async throws -> StudioAlbumRecord {
        let response = try await supabase
            .from("albums")
            .select()
            .eq("id", value: albumId.uuidString)
            .single()
            .execute()
        
        var album = try JSONDecoder().decode(StudioAlbumRecord.self, from: response.data)
        
        // Fetch artist name if not set
        if album.artist_name == nil || album.artist_name?.isEmpty == true {
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
                print("⚠️ Failed to fetch artist name: \(error.localizedDescription)")
            }
        }
        
        return album
    }

    // MARK: - UPDATE ALBUM
    func updateAlbum(
        _ album: StudioAlbumRecord,
        title: String?,
        artistName: String?,
        coverArtData: Data?,
        isPublic: Bool? = nil
    ) async throws -> StudioAlbumRecord {
        // Note: Permission check is handled by RLS policies
        // RLS allows both owners and collaborators (is_collaboration = true) to update albums
        
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
        let trimmedTitle = title?.trimmingCharacters(in: .whitespaces).isEmpty == false ? title?.trimmingCharacters(in: .whitespaces) : nil
        let trimmedArtistName = artistName?.trimmingCharacters(in: .whitespaces).isEmpty == false ? artistName?.trimmingCharacters(in: .whitespaces) : nil
        
        if trimmedTitle != nil || coverArtUrl != nil || trimmedArtistName != nil || isPublic != nil {
            struct UpdateDTO: Encodable {
                let title: String?
                let cover_art_url: String?
                let artist_name: String?
                let is_public: Bool?
            }
            
            let updateDTO = UpdateDTO(
                title: trimmedTitle,
                cover_art_url: coverArtUrl,
                artist_name: trimmedArtistName,
                is_public: isPublic
            )
            
            print("🔄 Updating album \(album.id.uuidString) with title: \(trimmedTitle ?? "nil"), artistName: \(trimmedArtistName ?? "nil"), coverArtUrl: \(coverArtUrl != nil ? "set" : "nil"), isPublic: \(isPublic?.description ?? "nil")")
            
            try await supabase
                .from("albums")
                .update(updateDTO)
                .eq("id", value: album.id.uuidString)
                .execute()
            
            print("✅ Album updated successfully")
        }
        
        // Fetch and return updated album
        // artist_name is now stored directly on the album, so no need to fetch from studio_artists
        let response = try await supabase
            .from("albums")
            .select()
            .eq("id", value: album.id.uuidString)
            .single()
            .execute()
        
        let updatedAlbum = try JSONDecoder().decode(StudioAlbumRecord.self, from: response.data)
        
        return updatedAlbum
    }

    // MARK: - DELETE ALBUM
    func deleteAlbum(_ album: StudioAlbumRecord) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Check if user is the owner
        let isOwner = album.artist_id.uuidString == userId
        
        if isOwner {
            // User owns the album - delete completely
            try await supabase
                .from("albums")
                .delete()
                .eq("id", value: album.id.uuidString)
                .execute()
            print("✅ Deleted album \(album.id.uuidString) completely (user is owner)")
        } else {
            // User is not the owner - remove from shared_albums only
            try await removeSharedAlbum(albumId: album.id, userId: userId)
            print("✅ Removed album \(album.id.uuidString) from user's library (user is not owner)")
        }
    }
    
    // MARK: - REMOVE SHARED ALBUM
    // Removes a shared album from user's library without deleting the original
    func removeSharedAlbum(albumId: UUID, userId: String) async throws {
        try await supabase
            .from("shared_albums")
            .delete()
            .eq("album_id", value: albumId.uuidString)
            .eq("shared_with", value: userId)
            .execute()
    }
    
    // MARK: - DELETE ALBUM (WITH CONTEXT)
    // Allows explicit control over delete behavior based on context
    func deleteAlbum(_ album: StudioAlbumRecord, context: AlbumDeleteContext) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        switch context {
        case .myAlbums:
            // Always delete completely from "My Albums"
            try await supabase
                .from("albums")
                .delete()
                .eq("id", value: album.id.uuidString)
                .execute()
            print("✅ Deleted album \(album.id.uuidString) completely (from My Albums)")
            
        case .sharedWithYou:
            // Remove from shared_albums only (view-only share)
            try await removeSharedAlbum(albumId: album.id, userId: userId)
            print("✅ Removed album \(album.id.uuidString) from user's library (from Shared with You)")
            
        case .collaborations:
            // For collaborations, we need to check if user wants to leave or delete
            // This method is for complete deletion - use deleteAlbumCompletely instead
            // But keeping this for backward compatibility
            try await deleteAlbumCompletely(album, context: context)
        }
    }
    
    // MARK: - DELETE ALBUM COMPLETELY
    // Explicitly deletes the album completely (for collaborations, this removes it for everyone)
    func deleteAlbumCompletely(_ album: StudioAlbumRecord, context: AlbumDeleteContext) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        switch context {
        case .myAlbums:
            // Delete completely
            try await supabase
                .from("albums")
                .delete()
                .eq("id", value: album.id.uuidString)
                .execute()
            print("✅ Deleted album \(album.id.uuidString) completely (from My Albums)")
            
        case .sharedWithYou:
            // For shared albums, complete deletion means removing from library
            // (can't delete someone else's album)
            try await removeSharedAlbum(albumId: album.id, userId: userId)
            print("✅ Removed album \(album.id.uuidString) from user's library (from Shared with You)")
            
        case .collaborations:
            // Delete completely - removes for all collaborators
            try await supabase
                .from("albums")
                .delete()
                .eq("id", value: album.id.uuidString)
                .execute()
            print("✅ Deleted album \(album.id.uuidString) completely (from Collaborations)")
        }
    }
    
    // MARK: - LEAVE COLLABORATION
    // Removes user from collaboration without deleting the album
    func leaveCollaboration(album: StudioAlbumRecord) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Remove from shared_albums (leaves collaboration)
        try await removeSharedAlbum(albumId: album.id, userId: userId)
        print("✅ User \(userId) left collaboration for album \(album.id.uuidString)")
    }
    
    // MARK: - SEARCH PUBLIC ALBUMS BY USER
    /// Searches for public albums owned by users matching the given email or username
    /// Uses search_users_paginated to find users, then fetches their public albums
    func searchPublicAlbumsByUser(query: String, limit: Int = 50) async throws -> [StudioAlbumRecord] {
        let searchQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !searchQuery.isEmpty else {
            return []
        }
        
        print("🔍 Searching for public albums by user: \(searchQuery)")
        
        // Use the existing user search RPC to find matching users by email or username
        let socialService = SupabaseSocialGraphService.shared
        
        var matchingUserIds: [UUID] = []
        
        do {
            // Search for users - this supports both email and username
            let (users, _) = try await socialService.searchUsersPaginated(query: searchQuery, limit: 20, offset: 0)
            matchingUserIds = users.compactMap { UUID(uuidString: $0.id) }
        } catch {
            print("⚠️ Could not search users: \(error.localizedDescription)")
            // Fallback to direct profile search by username only
            do {
                struct ProfileResponse: Codable {
                    let id: UUID
                }
                
                let cleanQuery = searchQuery.hasPrefix("@") ? String(searchQuery.dropFirst()) : searchQuery
                let profileResponse = try await supabase
                    .from("profiles")
                    .select("id")
                    .ilike("username", pattern: "%\(cleanQuery)%")
                    .limit(20)
                    .execute()
                
                let profiles = try JSONDecoder().decode([ProfileResponse].self, from: profileResponse.data)
                matchingUserIds = profiles.map { $0.id }
            } catch {
                print("⚠️ Fallback search also failed: \(error.localizedDescription)")
                return []
            }
        }
        
        guard !matchingUserIds.isEmpty else {
            print("ℹ️ No matching users found")
            return []
        }
        
        print("✅ Found \(matchingUserIds.count) matching user(s)")
        
        // Fetch public albums for matching users
        var allAlbums: [StudioAlbumRecord] = []
        
        for userId in matchingUserIds {
            do {
                let response = try await supabase
                    .from("albums")
                    .select()
                    .eq("artist_id", value: userId.uuidString)
                    .eq("is_public", value: true)
                    .order("created_at", ascending: false)
                    .execute()
                
                let userAlbums = try JSONDecoder().decode([StudioAlbumRecord].self, from: response.data)
                allAlbums.append(contentsOf: userAlbums)
                
                if allAlbums.count >= limit {
                    break
                }
            } catch {
                print("⚠️ Failed to fetch albums for user \(userId): \(error.localizedDescription)")
            }
        }
        
        // Limit results
        allAlbums = Array(allAlbums.prefix(limit))
        
        // Fetch artist names for albums that don't have them
        let albumsNeedingArtistName = allAlbums.filter { $0.artist_name == nil || $0.artist_name?.isEmpty == true }
        let uniqueArtistIds = Set(albumsNeedingArtistName.map { $0.artist_id })
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
        return allAlbums.map { album in
            var updatedAlbum = album
            if updatedAlbum.artist_name == nil || updatedAlbum.artist_name?.isEmpty == true {
                updatedAlbum.artist_name = artistNames[album.artist_id]
            }
            return updatedAlbum
        }
    }
    
    // MARK: - FETCH PUBLIC ALBUMS BY USER ID
    /// Fetches all public albums for a specific user
    func fetchPublicAlbumsByUserId(userId: UUID) async throws -> [StudioAlbumRecord] {
        print("🔍 Fetching public albums for user: \(userId.uuidString)")
        
        let response = try await supabase
            .from("albums")
            .select()
            .eq("artist_id", value: userId.uuidString)
            .eq("is_public", value: true)
            .order("created_at", ascending: false)
            .execute()
        
        var albums = try JSONDecoder().decode([StudioAlbumRecord].self, from: response.data)
        
        // Fetch artist names for albums that don't have them
        let albumsNeedingArtistName = albums.filter { $0.artist_name == nil || $0.artist_name?.isEmpty == true }
        let uniqueArtistIds = Set(albumsNeedingArtistName.map { $0.artist_id })
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
            if updatedAlbum.artist_name == nil || updatedAlbum.artist_name?.isEmpty == true {
                updatedAlbum.artist_name = artistNames[album.artist_id]
            }
            return updatedAlbum
        }
    }
    
    // MARK: - DELETE CONTEXT
    enum AlbumDeleteContext {
        case myAlbums      // User owns the album
        case sharedWithYou // View-only share
        case collaborations // Collaborative album
    }
}

