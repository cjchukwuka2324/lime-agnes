import Foundation
import Supabase

// MARK: - Protocol

protocol NotificationService {
    func fetchNotifications(limit: Int, before: Date?) async throws -> [AppNotification]
    func markAsRead(id: String) async throws
    func markAllAsRead() async throws
    func getUnreadCount() async throws -> Int
}

// MARK: - Supabase Implementation

final class SupabaseNotificationService: NotificationService {
    static let shared = SupabaseNotificationService()
    
    private let client = SupabaseService.shared.client
    
    private init() {}
    
    // MARK: - Fetch Notifications
    
    func fetchNotifications(limit: Int = 50, before: Date? = nil) async throws -> [AppNotification] {
        guard let currentUserId = client.auth.currentUser?.id else {
            print("🔔❌ NotificationService: User not authenticated")
            throw NSError(domain: "NotificationService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("🔔 NotificationService: Fetching notifications for user \(currentUserId.uuidString)")
        
        // Build query
        let response = try await client
            .from("notifications")
            .select("""
                id,
                type,
                message,
                created_at,
                read_at,
                post_id,
                rocklist_id,
                old_rank,
                new_rank,
                actor:actor_id (
                    id,
                    display_name,
                    first_name,
                    last_name,
                    username,
                    profile_picture_url,
                    region
                )
            """)
            .eq("user_id", value: currentUserId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        
        print("🔔 NotificationService: Response data size: \(response.data.count) bytes")
        print("🔔 NotificationService: Response preview: \(String(data: response.data.prefix(200), encoding: .utf8) ?? "nil")")
        
        // Parse response
        let decoder = JSONDecoder()
        // Don't use convertFromSnakeCase when we have custom CodingKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
        }
        
        let notifications: [NotificationRow] = try decoder.decode([NotificationRow].self, from: response.data)
        print("🔔 NotificationService: Successfully decoded \(notifications.count) notifications")
        
        // Map to AppNotification
        return notifications.map { row in
            AppNotification(
                id: row.id,
                type: row.type,
                message: row.message,
                createdAt: row.createdAt,
                readAt: row.readAt,
                actor: row.actor.map { actorRow in
                    let displayName: String
                    if let dn = actorRow.displayName, !dn.isEmpty {
                        displayName = dn
                    } else if let first = actorRow.firstName, let last = actorRow.lastName {
                        displayName = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
                    } else if let username = actorRow.username {
                        displayName = username
                    } else {
                        displayName = "User"
                    }
                    
                    let handle: String
                    if let username = actorRow.username {
                        handle = "@\(username)"
                    } else {
                        handle = "@user"
                    }
                    
                    let initials: String
                    if let first = actorRow.firstName, let last = actorRow.lastName {
                        initials = "\(first.prefix(1))\(last.prefix(1))".uppercased()
                    } else {
                        initials = String(displayName.prefix(2)).uppercased()
                    }
                    
                    return UserSummary(
                        id: actorRow.id,
                        displayName: displayName,
                        handle: handle,
                        avatarInitials: initials,
                        profilePictureURL: actorRow.profilePictureUrl.flatMap { URL(string: $0) },
                        isFollowing: false,
                        region: actorRow.region,
                        followersCount: 0,
                        followingCount: 0
                    )
                },
                postId: row.postId,
                rocklistId: row.rocklistId,
                oldRank: row.oldRank,
                newRank: row.newRank
            )
        }
    }
    
    // MARK: - Mark as Read
    
    func markAsRead(id: String) async throws {
        guard let currentUserId = client.auth.currentUser?.id else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nowString = isoFormatter.string(from: now)
        
        struct UpdatePayload: Encodable {
            let readAt: String
            
            enum CodingKeys: String, CodingKey {
                case readAt = "read_at"
            }
        }
        
        try await client
            .from("notifications")
            .update(UpdatePayload(readAt: nowString))
            .eq("id", value: id)
            .eq("user_id", value: currentUserId.uuidString)
            .execute()
    }
    
    // MARK: - Mark All as Read
    
    func markAllAsRead() async throws {
        guard let currentUserId = client.auth.currentUser?.id else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let now = Date()
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let nowString = isoFormatter.string(from: now)
        
        struct UpdatePayload: Encodable {
            let readAt: String
            
            enum CodingKeys: String, CodingKey {
                case readAt = "read_at"
            }
        }
        
        try await client
            .from("notifications")
            .update(UpdatePayload(readAt: nowString))
            .eq("user_id", value: currentUserId.uuidString)
            .is("read_at", value: nil)
            .execute()
    }
    
    // MARK: - Get Unread Count
    
    func getUnreadCount() async throws -> Int {
        guard let currentUserId = client.auth.currentUser?.id else {
            throw NSError(domain: "NotificationService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        struct CountResponse: Decodable {
            let count: Int
        }
        
        let response = try await client
            .from("notifications")
            .select("*", head: false, count: .exact)
            .eq("user_id", value: currentUserId.uuidString)
            .is("read_at", value: nil)
            .execute()
        
        // Extract count from response headers
        if let countString = response.response.value(forHTTPHeaderField: "Content-Range"),
           let count = Int(countString.components(separatedBy: "/").last ?? "0") {
            return count
        }
        
        return 0
    }
}

// MARK: - Helper Models

private struct NotificationRow: Decodable {
    let id: String
    let type: String
    let message: String
    let createdAt: Date
    let readAt: Date?
    let postId: String?
    let rocklistId: String?
    let oldRank: Int?
    let newRank: Int?
    let actor: ActorRow?
    
    enum CodingKeys: String, CodingKey {
        case id, type, message, actor
        case createdAt = "created_at"
        case readAt = "read_at"
        case postId = "post_id"
        case rocklistId = "rocklist_id"
        case oldRank = "old_rank"
        case newRank = "new_rank"
    }
}

private struct ActorRow: Decodable {
    let id: String
    let displayName: String?
    let firstName: String?
    let lastName: String?
    let username: String?
    let profilePictureUrl: String?
    let region: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case firstName = "first_name"
        case lastName = "last_name"
        case username, region
        case profilePictureUrl = "profile_picture_url"
    }
}