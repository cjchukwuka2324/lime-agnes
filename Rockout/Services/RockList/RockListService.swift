import Foundation
import Supabase

final class RockListService {
    static let shared = RockListService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - RPC Parameter Structs
    
    private struct RockListParams: Encodable {
        let p_artist_id: String
        let p_start_timestamp: String
        let p_end_timestamp: String
        let p_region: String?
    }
    
    private struct MyRockListSummaryParams: Encodable {
        let p_start_timestamp: String
        let p_end_timestamp: String
        let p_region: String?
    }
    
    private struct PostCommentParams: Encodable {
        let p_artist_id: String
        let p_content: String
        let p_region: String?
    }
    
    private struct GetCommentsParams: Encodable {
        let p_artist_id: String
        let p_start_timestamp: String
        let p_end_timestamp: String
    }
    
    private struct GetScoreBreakdownParams: Encodable {
        let p_user_id: String
        let p_artist_id: String
        let p_region: String?
    }
    
    // MARK: - Date Formatter
    
    private var dateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
    
    // MARK: - Fetch RockList
    
    func fetchRockList(
        artistId: String,
        startDate: Date,
        endDate: Date,
        region: String?
    ) async throws -> RockListResponse {
        
        let params = RockListParams(
            p_artist_id: artistId,
            p_start_timestamp: dateFormatter.string(from: startDate),
            p_end_timestamp: dateFormatter.string(from: endDate),
            p_region: region
        )
        
        let response = try await supabase
            .rpc("get_rocklist_for_artist", params: params)
            .execute()
        
        let entries: [RockListEntry] = try JSONDecoder().decode(
            [RockListEntry].self,
            from: response.data
        )
        
        // Extract artist info from first entry (all entries have same artist)
        guard let firstEntry = entries.first else {
            throw NSError(
                domain: "RockListService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No RockList data found for artist"]
            )
        }
        
        let artist = ArtistSummary(
            id: firstEntry.artistId,
            name: firstEntry.artistName,
            imageURL: firstEntry.artistImageURL
        )
        
        // Separate top 20 and current user entry
        let top20 = Array(entries
            .filter { !$0.isCurrentUser }
            .sorted { $0.rank < $1.rank }
            .prefix(20))
        
        let currentUserEntry = entries.first { $0.isCurrentUser }
        
        return RockListResponse(
            artist: artist,
            top20: top20,
            currentUserEntry: currentUserEntry
        )
    }
    
    // MARK: - Fetch My RockList Summary
    
    func fetchMyRockListSummary(
        startDate: Date,
        endDate: Date,
        region: String?
    ) async throws -> [MyRockListRank] {
        
        let params = MyRockListSummaryParams(
            p_start_timestamp: dateFormatter.string(from: startDate),
            p_end_timestamp: dateFormatter.string(from: endDate),
            p_region: region
        )
        
        let response = try await supabase
            .rpc("get_my_rocklist_summary", params: params)
            .execute()
        
        let ranks: [MyRockListRank] = try JSONDecoder().decode(
            [MyRockListRank].self,
            from: response.data
        )
        
        // Sort by rank ascending (best rank first)
        return ranks.sorted { rank1, rank2 in
            switch (rank1.myRank, rank2.myRank) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            case (let r1?, let r2?): return r1 < r2
            }
        }
    }
    
    // MARK: - Post RockList Comment
    
    func postRockListComment(
        artistId: String,
        content: String,
        region: String?
    ) async throws -> RockListComment {
        
        let params = PostCommentParams(
            p_artist_id: artistId,
            p_content: content,
            p_region: region
        )
        
        let response = try await supabase
            .rpc("post_rocklist_comment", params: params)
            .execute()
        
        let comments: [RockListComment] = try JSONDecoder().decode(
            [RockListComment].self,
            from: response.data
        )
        
        guard let comment = comments.first else {
            throw NSError(
                domain: "RockListService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create comment"]
            )
        }
        
        return comment
    }
    
    // MARK: - Fetch RockList Comments
    
    func fetchRockListComments(
        artistId: String,
        startDate: Date,
        endDate: Date
    ) async throws -> [RockListComment] {
        
        let params = GetCommentsParams(
            p_artist_id: artistId,
            p_start_timestamp: dateFormatter.string(from: startDate),
            p_end_timestamp: dateFormatter.string(from: endDate)
        )
        
        let response = try await supabase
            .rpc("get_rocklist_comments_for_artist", params: params)
            .execute()
        
        let comments: [RockListComment] = try JSONDecoder().decode(
            [RockListComment].self,
            from: response.data
        )
        
        return comments
    }
    
    // MARK: - Get Score Breakdown
    
    func getScoreBreakdown(
        userId: UUID,
        artistId: String,
        region: String? = nil
    ) async throws -> ListenerScoreBreakdown {
        
        let params = GetScoreBreakdownParams(
            p_user_id: userId.uuidString,
            p_artist_id: artistId,
            p_region: region ?? "GLOBAL"
        )
        
        let response = try await supabase
            .rpc("get_listener_score_breakdown", params: params)
            .execute()
        
        // The function returns JSONB, so we need to decode it
        let jsonData = response.data
        
        // Check for error in response
        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let error = json["error"] as? String {
            throw NSError(
                domain: "RockListService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: error]
            )
        }
        
        // Decode the breakdown
        let breakdown = try JSONDecoder().decode(
            ListenerScoreBreakdown.self,
            from: jsonData
        )
        
        return breakdown
    }
}

