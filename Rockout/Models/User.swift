import Foundation

struct User: Identifiable, Codable {
    let id: UUID
    let email: String
    let createdAt: Date
}
