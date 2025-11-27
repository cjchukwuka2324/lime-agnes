import Foundation

struct SpotifyConnection: Codable, Identifiable {
    let id: UUID
    let user_id: UUID
    let spotify_user_id: String
    let access_token: String
    let refresh_token: String
    let expires_at: String
    let connected_at: String
    var display_name: String?
    var email: String?
}

struct SpotifyConnectionDTO: Encodable {
    let user_id: String
    let spotify_user_id: String
    let access_token: String
    let refresh_token: String
    let expires_at: String
    let display_name: String?
    let email: String?
}

