import Foundation
import SwiftUI

@MainActor
final class PostDetailViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var rootPost: Post?
    @Published var replies: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let postId: String
    private let service: FeedService
    
    // MARK: - Initialization
    
    init(postId: String, service: FeedService = InMemoryFeedService.shared) {
        self.postId = postId
        self.service = service
    }
    
    // MARK: - Load Thread
    
    func loadThread() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let (root, replies) = try await service.fetchThread(for: postId)
            self.rootPost = root
            self.replies = replies
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading thread: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Refresh
    
    func refresh() async {
        await loadThread()
    }
}
