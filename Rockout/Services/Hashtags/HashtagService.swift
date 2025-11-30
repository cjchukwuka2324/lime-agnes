import Foundation
import Supabase

// MARK: - Hashtag Models

struct TrendingHashtag: Identifiable, Hashable {
    let id = UUID()
    let tag: String // Without # symbol
    let postCount: Int
    let engagementScore: Double
    let latestPostAt: Date
    
    var displayTag: String {
        "#\(tag)"
    }
}

// MARK: - HashtagService Protocol

protocol HashtagService {
    func getTrendingHashtags(timeWindowHours: Int, limit: Int) async throws -> [TrendingHashtag]
    func getPostsByHashtag(tag: String, cursor: Date?, limit: Int) async throws -> (posts: [Post], hasMore: Bool)
    func getAllTrendingPosts(timeWindowHours: Int, cursor: Date?, limit: Int) async throws -> (posts: [Post], hasMore: Bool)
}

// MARK: - Supabase Implementation

final class SupabaseHashtagService: HashtagService {
    static let shared = SupabaseHashtagService()
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    // MARK: - Shared Data Structures
    
    private struct FeedPostRow: Decodable {
        let id: UUID
        let user_id: UUID
        let text: String
        let created_at: String
        let like_count: Int
        let is_liked_by_current_user: Bool
        let reply_count: Int
        let author_display_name: String
        let author_handle: String
        let author_avatar_initials: String
        let author_instagram_handle: String?
        let author_twitter_handle: String?
        let author_tiktok_handle: String?
        let image_urls: [String]?
        let video_url: String?
        let audio_url: String?
        let parent_post_id: UUID?
        let leaderboard_entry_id: String?
        let leaderboard_artist_name: String?
        let leaderboard_rank: Int?
        let leaderboard_percentile_label: String?
        let leaderboard_minutes_listened: Int?
        let reshared_post_id: UUID?
        let author_profile_picture_url: String?
        let spotify_link_url: String?
        let spotify_link_type: String?
        let spotify_link_data: [String: SupabaseFeedService.AnyCodable]?
        let poll_question: String?
        let poll_type: String?
        let poll_options: SupabaseFeedService.AnyCodable?
        let background_music_spotify_id: String?
        let background_music_data: [String: SupabaseFeedService.AnyCodable]?
    }
    
    // MARK: - Get Trending Hashtags
    
    func getTrendingHashtags(timeWindowHours: Int = 72, limit: Int = 10) async throws -> [TrendingHashtag] {
        struct GetTrendingParams: Encodable {
            let p_time_window_hours: Int
            let p_limit: Int
        }
        
        let params = GetTrendingParams(
            p_time_window_hours: timeWindowHours,
            p_limit: limit
        )
        
        let response = try await supabase
            .rpc("get_trending_hashtags", params: params)
            .execute()
        
        // Decode response
        struct TrendingRow: Decodable {
            let tag: String
            let post_count: Int
            let engagement_score: Double
            let latest_post_at: String
        }
        
        let decoder = JSONDecoder()
        let rows = try decoder.decode([TrendingRow].self, from: response.data)
        
        // Convert to TrendingHashtag models
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return rows.compactMap { row in
            guard let date = formatter.date(from: row.latest_post_at) else {
                return nil
            }
            
            return TrendingHashtag(
                tag: row.tag,
                postCount: row.post_count,
                engagementScore: row.engagement_score,
                latestPostAt: date
            )
        }
    }
    
    // MARK: - Get Posts by Hashtag
    
    func getPostsByHashtag(tag: String, cursor: Date? = nil, limit: Int = 20) async throws -> (posts: [Post], hasMore: Bool) {
        // Normalize tag (remove # if present)
        let normalizedTag = tag.replacingOccurrences(of: "#", with: "").lowercased()
        
        // Convert cursor to ISO8601 string
        let cursorString: String?
        if let cursor = cursor {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            cursorString = formatter.string(from: cursor)
        } else {
            cursorString = nil
        }
        
        struct GetPostsByHashtagParams: Encodable {
            let p_tag: String
            let p_limit: Int
            let p_cursor: String?
        }
        
        let params = GetPostsByHashtagParams(
            p_tag: normalizedTag,
            p_limit: limit,
            p_cursor: cursorString
        )
        
        print("🏷️ Fetching posts for hashtag: #\(normalizedTag), cursor: \(cursorString ?? "nil")")
        
        let response = try await supabase
            .rpc("get_posts_by_hashtag", params: params)
            .execute()
        
        let decoder = JSONDecoder()
        let rows = try decoder.decode([FeedPostRow].self, from: response.data)
        
        print("✅ Fetched \(rows.count) posts for hashtag #\(normalizedTag)")
        
        // Convert rows to Post objects
        let posts = try rows.map { row -> Post in
            try convertFeedRowToPost(row: row)
        }
        
        // Determine if there are more pages
        let hasMore = posts.count == limit
        
        return (posts: posts, hasMore: hasMore)
    }
    
    // MARK: - Get All Trending Posts
    
    func getAllTrendingPosts(timeWindowHours: Int = 72, cursor: Date? = nil, limit: Int = 50) async throws -> (posts: [Post], hasMore: Bool) {
        // Convert cursor to ISO8601 string
        let cursorString: String?
        if let cursor = cursor {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            cursorString = formatter.string(from: cursor)
        } else {
            cursorString = nil
        }
        
        struct GetAllTrendingParams: Encodable {
            let p_limit: Int
            let p_time_window_hours: Int
            let p_cursor: String?
        }
        
        let params = GetAllTrendingParams(
            p_limit: limit,
            p_time_window_hours: timeWindowHours,
            p_cursor: cursorString
        )
        
        print("🔥 Fetching all trending posts, cursor: \(cursorString ?? "nil")")
        
        let response = try await supabase
            .rpc("get_all_trending_posts", params: params)
            .execute()
        
        let decoder = JSONDecoder()
        let rows = try decoder.decode([FeedPostRow].self, from: response.data)
        
        print("✅ Fetched \(rows.count) trending posts")
        
        // Convert rows to Post objects
        let posts = try rows.map { row -> Post in
            try convertFeedRowToPost(row: row)
        }
        
        // Determine if there are more pages
        let hasMore = posts.count == limit
        
        return (posts: posts, hasMore: hasMore)
    }
    
    // MARK: - Helper: Convert FeedPostRow to Post
    
    private func convertFeedRowToPost(row: FeedPostRow) throws -> Post {
        // Parse date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let createdAt = formatter.date(from: row.created_at) else {
            throw NSError(domain: "HashtagService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid date format"])
        }
        
        // Create author with social media handles
        let author = UserSummary(
            id: row.user_id.uuidString,
            displayName: row.author_display_name,
            handle: row.author_handle,
            avatarInitials: row.author_avatar_initials,
            profilePictureURL: row.author_profile_picture_url.flatMap { URL(string: $0) },
            isFollowing: false,
            region: nil,
            followersCount: 0,
            followingCount: 0,
            instagramHandle: row.author_instagram_handle,
            twitterHandle: row.author_twitter_handle,
            tiktokHandle: row.author_tiktok_handle
        )
        
        // Extract optional fields
        let imageURLs = row.image_urls?.compactMap { URL(string: $0) } ?? []
        let videoURL = row.video_url.flatMap { URL(string: $0) }
        let audioURL = row.audio_url.flatMap { URL(string: $0) }
        
        // Create Post
        return Post(
            id: row.id.uuidString,
            text: row.text,
            createdAt: createdAt,
            author: author,
            imageURLs: imageURLs,
            videoURL: videoURL,
            audioURL: audioURL,
            likeCount: row.like_count,
            replyCount: row.reply_count,
            isLiked: row.is_liked_by_current_user,
            parentPostId: row.parent_post_id?.uuidString,
            parentPost: nil,
            leaderboardEntry: nil,
            resharedPostId: row.reshared_post_id?.uuidString,
            spotifyLink: nil,
            poll: nil,
            backgroundMusic: nil
        )
    }
    
    // MARK: - Helper: Convert Row to Post (Legacy - for dict-based rows)
    
    private func convertRowToPost(row: Any) throws -> Post {
        // Use reflection to convert the row to Post
        // This is a simplified version - in production, you'd want more robust parsing
        
        guard let rowDict = row as? [String: Any] else {
            throw NSError(domain: "HashtagService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert row"])
        }
        
        // Extract basic fields
        guard let idString = rowDict["id"] as? String,
              let id = UUID(uuidString: idString),
              let userIdString = rowDict["user_id"] as? String,
              let userId = UUID(uuidString: userIdString),
              let text = rowDict["text"] as? String,
              let createdAtString = rowDict["created_at"] as? String,
              let likeCount = rowDict["like_count"] as? Int,
              let isLiked = rowDict["is_liked_by_current_user"] as? Bool,
              let replyCount = rowDict["reply_count"] as? Int,
              let authorDisplayName = rowDict["author_display_name"] as? String,
              let authorHandle = rowDict["author_handle"] as? String,
              let authorInitials = rowDict["author_avatar_initials"] as? String else {
            throw NSError(domain: "HashtagService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
        }
        
        // Parse date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let createdAt = formatter.date(from: createdAtString) else {
            throw NSError(domain: "HashtagService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid date format"])
        }
        
        // Create author with social media handles
        let author = UserSummary(
            id: userId.uuidString,
            displayName: authorDisplayName,
            handle: authorHandle,
            avatarInitials: authorInitials,
            profilePictureURL: (rowDict["author_profile_picture_url"] as? String).flatMap { URL(string: $0) },
            isFollowing: false,
            region: nil,
            followersCount: 0,
            followingCount: 0,
            instagramHandle: rowDict["author_instagram_handle"] as? String,
            twitterHandle: rowDict["author_twitter_handle"] as? String,
            tiktokHandle: rowDict["author_tiktok_handle"] as? String
        )
        
        // Extract optional fields
        let imageURLs = (rowDict["image_urls"] as? [String])?.compactMap { URL(string: $0) } ?? []
        let videoURL = (rowDict["video_url"] as? String).flatMap { URL(string: $0) }
        let audioURL = (rowDict["audio_url"] as? String).flatMap { URL(string: $0) }
        
        // Create Post (simplified - you may need to add more fields)
        return Post(
            id: id.uuidString,
            text: text,
            createdAt: createdAt,
            author: author,
            imageURLs: imageURLs,
            videoURL: videoURL,
            audioURL: audioURL,
            likeCount: likeCount,
            replyCount: replyCount,
            isLiked: isLiked,
            parentPostId: nil,
            parentPost: nil,
            leaderboardEntry: nil,
            resharedPostId: nil,
            spotifyLink: nil,
            poll: nil,
            backgroundMusic: nil
        )
    }
}