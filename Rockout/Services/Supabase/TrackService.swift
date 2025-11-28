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

        // Determine the track number
        let finalTrackNumber: Int
        if let requestedNumber = trackNumber, requestedNumber > 0 {
            // Renumber existing tracks to make room
            try await renumberTracksForInsertion(albumId: album.id, insertAt: requestedNumber)
            finalTrackNumber = requestedNumber
        } else {
            // Get the next track number (highest + 1)
            let existingTracks = try await fetchTracks(for: album.id)
            finalTrackNumber = (existingTracks.map { $0.track_number ?? 0 }.max() ?? 0) + 1
        }

        let dto = CreateTrackDTO(
            album_id: album.id.uuidString,
            artist_id: userId,
            title: title,
            audio_url: audioUrl.absoluteString,
            duration: duration ?? 0,
            track_number: finalTrackNumber
        )

        let response = try await supabase
            .from("tracks")
            .insert(dto)
            .select()
            .single()
            .execute()

        return try JSONDecoder().decode(StudioTrackRecord.self, from: response.data)
    }
    
    // MARK: - RENUMBER TRACKS FOR INSERTION
    private func renumberTracksForInsertion(albumId: UUID, insertAt: Int) async throws {
        // Fetch all tracks for this album
        let tracks = try await fetchTracks(for: albumId)
        
        // Update tracks that need to be shifted
        for track in tracks {
            if let currentNumber = track.track_number, currentNumber >= insertAt {
                // Increment track number by 1
                struct UpdateDTO: Encodable {
                    let track_number: Int
                }
                
                let updateDTO = UpdateDTO(track_number: currentNumber + 1)
                
                try await supabase
                    .from("tracks")
                    .update(updateDTO)
                    .eq("id", value: track.id.uuidString)
                    .execute()
            }
        }
    }
    
    // MARK: - REORDER TRACKS
    func reorderTracks(albumId: UUID, trackOrder: [(trackId: UUID, newNumber: Int)]) async throws {
        // Update each track's number
        for (trackId, newNumber) in trackOrder {
            struct UpdateDTO: Encodable {
                let track_number: Int
            }
            
            let updateDTO = UpdateDTO(track_number: newNumber)
            
            try await supabase
                .from("tracks")
                .update(updateDTO)
                .eq("id", value: trackId.uuidString)
                .execute()
        }
    }
    
    // MARK: - UPDATE TRACK
    func updateTrack(_ track: StudioTrackRecord, title: String?, trackNumber: Int?) async throws {
        struct UpdateDTO: Encodable {
            let title: String?
            let track_number: Int?
        }
        
        let updateDTO = UpdateDTO(
            title: title,
            track_number: trackNumber
        )
        
        // Only update if at least one field is provided
        guard title != nil || trackNumber != nil else { return }
        
        try await supabase
            .from("tracks")
            .update(updateDTO)
            .eq("id", value: track.id.uuidString)
            .execute()
    }

    // MARK: - FETCH TRACKS (UUID VERSION)
    func fetchTracks(for albumId: UUID) async throws -> [StudioTrackRecord] {
        print("🔍 Fetching tracks for album: \(albumId.uuidString)")
        
        do {
            let response = try await supabase
                .from("tracks")
                .select()
                .eq("album_id", value: albumId.uuidString)
                .order("track_number", ascending: true)
                .execute()

            let tracks = try JSONDecoder().decode([StudioTrackRecord].self, from: response.data)
            print("✅ Successfully fetched \(tracks.count) tracks for album \(albumId.uuidString)")
            return tracks
        } catch {
            print("❌ Error fetching tracks for album \(albumId.uuidString): \(error.localizedDescription)")
            throw error
        }
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
