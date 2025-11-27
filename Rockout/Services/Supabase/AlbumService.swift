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
    func createAlbum(title: String, coverArtData: Data?) async throws -> StudioAlbumRecord {

        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString

        // Upload cover art if provided
        var coverArtUrl: String? = nil

        if let data = coverArtData {
            let filename = "\(UUID().uuidString).jpg"
            let path = "album_covers/\(filename)"

            try await supabase.storage
                .from("studio")
                .upload(path: path, file: data)

            coverArtUrl = try supabase.storage
                .from("studio")
                .getPublicURL(path: path)
                .absoluteString
        }

        let dto = CreateAlbumDTO(
            title: title,
            artist_id: userId,
            release_status: "draft",
            cover_art_url: coverArtUrl
        )

        let response = try await supabase
            .from("albums")
            .insert(dto)
            .select()
            .single()
            .execute()

        return try JSONDecoder().decode(StudioAlbumRecord.self, from: response.data)
    }

    // MARK: - FETCH ALBUMS (NAME RESTORED)
    func fetchMyAlbums() async throws -> [StudioAlbumRecord] {

        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString

        let response = try await supabase
            .from("albums")
            .select()
            .eq("artist_id", value: userId)
            .order("created_at", ascending: false)
            .execute()

        return try JSONDecoder().decode([StudioAlbumRecord].self, from: response.data)
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
