import Foundation
import Supabase

final class PollVoteService {
    static let shared = PollVoteService()
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    // MARK: - Vote on Poll
    
    func voteOnPoll(postId: String, optionIndices: [Int]) async throws {
        guard let postUUID = UUID(uuidString: postId) else {
            throw NSError(domain: "PollVoteService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid post ID"])
        }
        
        struct VoteOnPollParams: Encodable {
            let p_post_id: UUID
            let p_option_indices: [Int]
        }
        
        try await supabase.rpc("vote_on_poll", params: VoteOnPollParams(
            p_post_id: postUUID,
            p_option_indices: optionIndices
        )).execute()
    }
    
    // MARK: - Get Poll Votes
    
    func getPollVotes(postId: String) async throws -> [Int: Int] {
        guard let postUUID = UUID(uuidString: postId) else {
            throw NSError(domain: "PollVoteService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid post ID"])
        }
        
        print("🔍 Fetching poll votes from database for post \(postId)")
        
        let response = try await supabase
            .from("post_poll_votes")
            .select("option_index")
            .eq("post_id", value: postUUID)
            .execute()
        
        struct VoteRow: Decodable {
            let option_index: Int
        }
        
        let votes: [VoteRow] = try JSONDecoder().decode([VoteRow].self, from: response.data)
        
        print("🔍 Found \(votes.count) total votes in database")
        
        // Count votes per option index
        var voteCounts: [Int: Int] = [:]
        for vote in votes {
            voteCounts[vote.option_index, default: 0] += 1
        }
        
        print("🔍 Vote counts by option: \(voteCounts)")
        
        return voteCounts
    }
    
    // MARK: - Get User Vote
    
    func getUserVote(postId: String) async throws -> [Int] {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            return []
        }
        
        guard let postUUID = UUID(uuidString: postId) else {
            throw NSError(domain: "PollVoteService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid post ID"])
        }
        
        let response = try await supabase
            .from("post_poll_votes")
            .select("option_index")
            .eq("post_id", value: postUUID)
            .eq("user_id", value: currentUserId)
            .execute()
        
        struct VoteRow: Decodable {
            let option_index: Int
        }
        
        let votes: [VoteRow] = try JSONDecoder().decode([VoteRow].self, from: response.data)
        return votes.map { $0.option_index }
    }
}
