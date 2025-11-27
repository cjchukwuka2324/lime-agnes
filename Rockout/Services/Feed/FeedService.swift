import Foundation
import Supabase

final class FeedService {
    static let shared = FeedService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - RPC Parameter Struct
    
    private struct FollowingFeedParams: Encodable {
        let p_start_timestamp: String
        let p_end_timestamp: String
    }
    
    // MARK: - Date Formatter
    
    private var dateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
    
    // MARK: - Fetch Following Feed
    
    func fetchFollowingFeed(
        startDate: Date,
        endDate: Date
    ) async throws -> [FeedItem] {
        
        let params = FollowingFeedParams(
            p_start_timestamp: dateFormatter.string(from: startDate),
            p_end_timestamp: dateFormatter.string(from: endDate)
        )
        
        print("📡 Fetching feed from \(params.p_start_timestamp) to \(params.p_end_timestamp)")
        
        let response = try await supabase
            .rpc("get_following_feed", params: params)
            .execute()
        
        print("📦 Feed response received, data size: \(response.data.count) bytes")
        
        let feedItems: [FeedItem] = try JSONDecoder().decode(
            [FeedItem].self,
            from: response.data
        )
        
        print("✅ Decoded \(feedItems.count) feed items")
        
        return feedItems
    }
}

