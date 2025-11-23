import Foundation

struct TrackVersion: Codable, Identifiable {
    let id: UUID
    let track_id: UUID
    let version_number: Int
    let audio_url: String
    let created_at: String
    let created_by: UUID
    let notes: String? // Optional notes about this version
    let file_size: Int64? // File size in bytes
    let duration: Double?
}

struct TrackVersionDTO: Encodable {
    let track_id: String
    let version_number: Int
    let audio_url: String
    let created_by: String
    let notes: String?
    let file_size: Int64?
    let duration: Double?
}

