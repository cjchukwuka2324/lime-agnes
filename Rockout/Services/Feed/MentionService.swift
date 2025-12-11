import Foundation

/// Service for fetching user suggestions for @mentions
protocol MentionService {
    func searchUsers(query: String) async throws -> [UserSummary]
}

class SupabaseMentionService: MentionService {
    static let shared = SupabaseMentionService()
    
    private let social: SocialGraphService
    
    init(social: SocialGraphService = SupabaseSocialGraphService.shared) {
        self.social = social
    }
    
    func searchUsers(query: String) async throws -> [UserSummary] {
        // Use existing social graph service to search users
        return try await social.searchUsers(query: query)
    }
}

