import Foundation
import Supabase

final class VersionService {
    static let shared = VersionService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Get Track Versions
    func getTrackVersions(for trackId: UUID) async throws -> [TrackVersion] {
        let response = try await supabase
            .from("track_versions")
            .select()
            .eq("track_id", value: trackId.uuidString)
            .order("version_number", ascending: false)
            .execute()
        
        return try JSONDecoder().decode([TrackVersion].self, from: response.data)
    }
    
    // MARK: - Create New Version
    func createTrackVersion(
        for track: StudioTrackRecord,
        audioData: Data,
        notes: String? = nil,
        duration: Double? = nil
    ) async throws -> TrackVersion {
        let session = try await supabase.auth.session
        let userId = session.user.id.uuidString
        
        // Get current version count
        let existingVersions = try await getTrackVersions(for: track.id)
        let nextVersionNumber = (existingVersions.first?.version_number ?? 0) + 1
        
        // Upload new audio version
        let filename = "v\(nextVersionNumber)_\(UUID().uuidString).m4a"
        let path = "tracks/\(track.album_id.uuidString)/\(track.id.uuidString)/versions/\(filename)"
        
        try await supabase.storage
            .from("studio")
            .upload(path: path, file: audioData)
        
        let audioUrl = try supabase.storage
            .from("studio")
            .getPublicURL(path: path)
        
        let fileSize = Int64(audioData.count)
        
        let dto = TrackVersionDTO(
            track_id: track.id.uuidString,
            version_number: nextVersionNumber,
            audio_url: audioUrl.absoluteString,
            created_by: userId,
            notes: notes,
            file_size: fileSize,
            duration: duration
        )
        
        let response = try await supabase
            .from("track_versions")
            .insert(dto)
            .select()
            .single()
            .execute()
        
        // Update main track audio_url to point to latest version
        try await supabase
            .from("tracks")
            .update(["audio_url": audioUrl.absoluteString])
            .eq("id", value: track.id.uuidString)
            .execute()
        
        return try JSONDecoder().decode(TrackVersion.self, from: response.data)
    }
    
    // MARK: - Restore Version
    func restoreTrackVersion(_ version: TrackVersion, to track: StudioTrackRecord) async throws {
        // Update track to use this version's audio
        try await supabase
            .from("tracks")
            .update(["audio_url": version.audio_url])
            .eq("id", value: track.id.uuidString)
            .execute()
    }
    
    // MARK: - Delete Version
    func deleteTrackVersion(_ version: TrackVersion) async throws {
        // Delete from database
        try await supabase
            .from("track_versions")
            .delete()
            .eq("id", value: version.id.uuidString)
            .execute()
        
        // Optionally delete from storage (be careful with this)
        // You might want to keep old versions for history
    }
}

