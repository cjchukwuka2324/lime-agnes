import Foundation

struct AppleMusicConnection: Codable, Identifiable {
    let id: UUID
    let user_id: UUID
    let apple_music_user_id: String
    let user_token: String
    let expires_at: String?
    let connected_at: String
    var display_name: String?
    var email: String?
}

struct AppleMusicConnectionDTO: Encodable {
    let user_id: String
    let apple_music_user_id: String
    let user_token: String
    let expires_at: String?
    let display_name: String?
    let email: String?
}

