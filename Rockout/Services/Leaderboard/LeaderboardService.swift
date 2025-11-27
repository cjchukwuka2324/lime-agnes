import Foundation
import Supabase

final class LeaderboardService {
    static let shared = LeaderboardService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - RPC Parameter Structs
    
    private struct ArtistLeaderboardParams: Encodable {
        let p_artist_id: String
        let p_start_timestamp: String
        let p_end_timestamp: String
        let p_region: String?
    }
    
    private struct MyArtistRanksParams: Encodable {
        let p_start_timestamp: String
        let p_end_timestamp: String
        let p_region: String?
    }
    
    // MARK: - Fetch Artist Leaderboard
    
    func fetchArtistLeaderboard(
        artistId: String,
        startDate: Date,
        endDate: Date,
        region: String?
    ) async throws -> ArtistLeaderboardResponse {
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let params = ArtistLeaderboardParams(
            p_artist_id: artistId,
            p_start_timestamp: formatter.string(from: startDate),
            p_end_timestamp: formatter.string(from: endDate),
            p_region: region
        )
        
        let response = try await supabase
            .rpc("get_artist_leaderboard", params: params)
            .execute()
        
        let entries: [ArtistLeaderboardEntry] = try JSONDecoder().decode(
            [ArtistLeaderboardEntry].self,
            from: response.data
        )
        
        // Extract artist info from first entry (all entries have same artist)
        guard let firstEntry = entries.first else {
            throw NSError(
                domain: "LeaderboardService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No leaderboard data found for artist"]
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
        
        // If current user is not in top 20, we need to ensure they're included
        // The RPC should handle this, but we'll verify
        var finalTop20 = top20
        if let currentUser = currentUserEntry,
           !top20.contains(where: { $0.userId == currentUser.userId }) {
            // Current user is outside top 20, but we still want to show top 20
            // The currentUserEntry is separate
        }
        
        return ArtistLeaderboardResponse(
            artist: artist,
            top20: finalTop20,
            currentUserEntry: currentUserEntry
        )
    }
    
    // MARK: - Fetch My Artist Ranks
    
    func fetchMyArtistRanks(
        startDate: Date,
        endDate: Date,
        region: String?
    ) async throws -> [MyArtistRank] {
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let params = MyArtistRanksParams(
            p_start_timestamp: formatter.string(from: startDate),
            p_end_timestamp: formatter.string(from: endDate),
            p_region: region
        )
        
        let response = try await supabase
            .rpc("get_my_followed_artists_ranks", params: params)
            .execute()
        
        let ranks: [MyArtistRank] = try JSONDecoder().decode(
            [MyArtistRank].self,
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
}

