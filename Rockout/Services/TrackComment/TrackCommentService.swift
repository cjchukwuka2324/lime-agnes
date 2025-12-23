import Foundation
import Supabase

final class TrackCommentService {
    static let shared = TrackCommentService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Create Comment
    
    func createComment(trackId: UUID, content: String, timestamp: Double) async throws -> TrackComment {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        // Get user's display name from profile
        let displayName = try await getUserDisplayName(userId: userId)
        
        struct CreateCommentDTO: Encodable {
            let track_id: String
            let user_id: String
            let content: String
            let timestamp: Double
        }
        
        let dto = CreateCommentDTO(
            track_id: trackId.uuidString,
            user_id: userId.uuidString,
            content: content,
            timestamp: timestamp
        )
        
        let response = try await supabase
            .from("ss_track_comments")
            .insert(dto)
            .select()
            .single()
            .execute()
        
        // Decode basic comment data
        let decoder = JSONDecoder()
        let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
        
        guard let json = json,
              let idString = json["id"] as? String,
              let id = UUID(uuidString: idString),
              let trackIdString = json["track_id"] as? String,
              let trackId = UUID(uuidString: trackIdString),
              let userIdString = json["user_id"] as? String,
              let userId = UUID(uuidString: userIdString),
              let content = json["content"] as? String,
              let timestamp = json["timestamp"] as? Double,
              let createdAtString = json["created_at"] as? String else {
            throw NSError(
                domain: "TrackCommentService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to decode comment response"]
            )
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = formatter.date(from: createdAtString) ?? Date()
        
        return TrackComment(
            id: id,
            trackId: trackId,
            userId: userId,
            displayName: displayName,
            content: content,
            timestamp: timestamp,
            createdAt: createdAt
        )
    }
    
    // MARK: - Get Comments
    
    func getComments(for trackId: UUID) async throws -> [TrackComment] {
        let response = try await supabase
            .from("ss_track_comments")
            .select()
            .eq("track_id", value: trackId.uuidString)
            .order("timestamp", ascending: true)
            .execute()
        
        // Decode array of comments
        let decoder = JSONDecoder()
        guard let jsonArray = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] else {
            return []
        }
        
        var comments: [TrackComment] = []
        
        for json in jsonArray {
            guard let idString = json["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let trackIdString = json["track_id"] as? String,
                  let trackId = UUID(uuidString: trackIdString),
                  let userIdString = json["user_id"] as? String,
                  let userId = UUID(uuidString: userIdString),
                  let content = json["content"] as? String,
                  let timestamp = json["timestamp"] as? Double,
                  let createdAtString = json["created_at"] as? String else {
                continue
            }
            
            // Fetch display name for each user
            let displayName = try await getUserDisplayName(userId: userId)
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let createdAt = formatter.date(from: createdAtString) ?? Date()
            
            comments.append(TrackComment(
                id: id,
                trackId: trackId,
                userId: userId,
                displayName: displayName,
                content: content,
                timestamp: timestamp,
                createdAt: createdAt
            ))
        }
        
        return comments
    }
    
    // MARK: - Delete Comment
    
    func deleteComment(commentId: UUID) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id
        
        // Verify the comment belongs to the user before deleting
        let response = try await supabase
            .from("ss_track_comments")
            .select("user_id")
            .eq("id", value: commentId.uuidString)
            .single()
            .execute()
        
        let decoder = JSONDecoder()
        let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any]
        
        guard let userIdString = json?["user_id"] as? String,
              let commentUserId = UUID(uuidString: userIdString),
              commentUserId == userId else {
            throw NSError(
                domain: "TrackCommentService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unauthorized: You can only delete your own comments"]
            )
        }
        
        try await supabase
            .from("ss_track_comments")
            .delete()
            .eq("id", value: commentId.uuidString)
            .execute()
    }
    
    // MARK: - Helper Methods
    
    private func getUserDisplayName(userId: UUID) async throws -> String {
        do {
            struct ProfileResponse: Codable {
                let display_name: String?
                let first_name: String?
                let last_name: String?
                let username: String?
            }
            
            let response = try await supabase
                .from("profiles")
                .select("display_name, first_name, last_name, username")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
            
            let profile = try JSONDecoder().decode(ProfileResponse.self, from: response.data)
            
            // Try display_name first
            if let displayName = profile.display_name, !displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                return displayName
            }
            
            // Fallback to first_name + last_name
            if let firstName = profile.first_name, let lastName = profile.last_name {
                let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                if !fullName.isEmpty {
                    return fullName
                }
            }
            
            // Fallback to username
            if let username = profile.username, !username.trimmingCharacters(in: .whitespaces).isEmpty {
                return username.capitalized
            }
        } catch {
            // Fall through to default
        }
        
        // Final fallback
        return "Anonymous"
    }
}
