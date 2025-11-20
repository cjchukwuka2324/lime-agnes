import Foundation

struct StudioAlbumRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let artist_id: UUID
    var title: String
    var cover_art_url: String?
    var release_status: String?
    var release_date: String?
}
