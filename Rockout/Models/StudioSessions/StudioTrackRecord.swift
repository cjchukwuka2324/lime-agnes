import Foundation

struct StudioTrackRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let album_id: UUID
    let artist_id: UUID
    var title: String
    var audio_url: String
    var duration: Double?
    var track_number: Int?
}
