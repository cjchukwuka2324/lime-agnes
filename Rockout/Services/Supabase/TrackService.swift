import Foundation
import Supabase

final class TrackService {
    static let shared = TrackService()
    private init() {}

    private let supabase = SupabaseService.shared.client

    struct CreateTrackDTO: Encodable {
        let album_id: String
        let artist_id: String
        let title: String
        let audio_url: String
        let duration: Double
        let track_number: Int
    }

    // MARK: - ADD TRACK
    func addTrack(
        to album: StudioAlbumRecord,
        title: String,
        audioData: Data,
        duration: Double?,
        trackNumber: Int?
    ) async throws -> StudioTrackRecord {

        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString

        // Upload audio
        let filename = "\(UUID().uuidString).m4a"
        let path = "tracks/\(album.id.uuidString)/\(filename)"

        try await supabase.storage
            .from("studio")
            .upload(path: path, file: audioData)

        let audioUrl = try supabase.storage
            .from("studio")
            .getPublicURL(path: path)

        let dto = CreateTrackDTO(
            album_id: album.id.uuidString,
            artist_id: userId,
            title: title,
            audio_url: audioUrl.absoluteString,
            duration: duration ?? 0,
            track_number: trackNumber ?? 1
        )

        let response = try await supabase
            .from("tracks")
            .insert(dto)
            .select()
            .single()
            .execute()

        return try JSONDecoder().decode(StudioTrackRecord.self, from: response.data)
    }

    // MARK: - FETCH TRACKS (UUID VERSION)
    func fetchTracks(for albumId: UUID) async throws -> [StudioTrackRecord] {

        let response = try await supabase
            .from("tracks")
            .select()
            .eq("album_id", value: albumId.uuidString)
            .order("track_number", ascending: true)
            .execute()

        return try JSONDecoder().decode([StudioTrackRecord].self, from: response.data)
    }

    // MARK: - FETCH TRACKS (MODEL VERSION)
    // This is the overload that fixes your AlbumDetailView error
    func fetchTracks(for album: StudioAlbumRecord) async throws -> [StudioTrackRecord] {
        try await fetchTracks(for: album.id)
    }

    // MARK: - DELETE TRACK
    func deleteTrack(_ track: StudioTrackRecord) async throws {
        try await supabase
            .from("tracks")
            .delete()
            .eq("id", value: track.id.uuidString)
            .execute()
    }
}
