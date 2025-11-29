import Foundation
import SwiftUI
import Supabase

@MainActor
final class PostDetailViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var rootPost: Post?
    @Published var replies: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Computed property for top-level replies (direct replies to root, not nested)
    var topLevelReplies: [Post] {
        guard let rootId = rootPost?.id else { return [] }
        return replies.filter { $0.parentPostId == rootId }
    }
    
    // MARK: - Private Properties
    
    private let postId: String
    private let service: FeedService
    
    // MARK: - Initialization
    
    init(postId: String, service: FeedService = SupabaseFeedService.shared) {
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
    
    // MARK: - Toggle Like
    
    func toggleLike(postId: String) async {
        // Optimistically update the UI
        if rootPost?.id == postId, let post = rootPost {
            let wasLiked = post.isLiked
            let updatedPost = Post(
                id: post.id,
                text: post.text,
                createdAt: post.createdAt,
                author: post.author,
                imageURLs: post.imageURLs,
                videoURL: post.videoURL,
                audioURL: post.audioURL,
                likeCount: wasLiked ? max(0, post.likeCount - 1) : post.likeCount + 1,
                replyCount: post.replyCount,
                isLiked: !wasLiked,
                parentPostId: post.parentPostId,
                parentPost: post.parentPost,
                leaderboardEntry: post.leaderboardEntry,
                resharedPostId: post.resharedPostId,
                spotifyLink: post.spotifyLink,
                poll: post.poll,
                backgroundMusic: post.backgroundMusic
            )
            rootPost = updatedPost
        } else if let index = replies.firstIndex(where: { $0.id == postId }) {
            let post = replies[index]
            let wasLiked = post.isLiked
            let updatedPost = Post(
                id: post.id,
                text: post.text,
                createdAt: post.createdAt,
                author: post.author,
                imageURLs: post.imageURLs,
                videoURL: post.videoURL,
                audioURL: post.audioURL,
                likeCount: wasLiked ? max(0, post.likeCount - 1) : post.likeCount + 1,
                replyCount: post.replyCount,
                isLiked: !wasLiked,
                parentPostId: post.parentPostId,
                parentPost: post.parentPost,
                leaderboardEntry: post.leaderboardEntry,
                resharedPostId: post.resharedPostId,
                spotifyLink: post.spotifyLink,
                poll: post.poll,
                backgroundMusic: post.backgroundMusic
            )
            replies[index] = updatedPost
        }
        
        do {
            _ = try await service.toggleLike(postId: postId)
            print("✅ Like toggled for post \(postId)")
        } catch {
            print("❌ Failed to toggle like: \(error)")
            errorMessage = "Failed to like post: \(error.localizedDescription)"
            // Revert on error by reloading
            await loadThread()
        }
    }
    
    // MARK: - Delete Post
    
    func deletePost(postId: String) async {
        // Optimistically update UI
        let deletedRootPost = rootPost
        let deletedReply = replies.first(where: { $0.id == postId })
        
        if rootPost?.id == postId {
            rootPost = nil
        }
        replies.removeAll { $0.id == postId }
        
        do {
            try await service.deletePost(postId: postId)
            print("✅ Post deleted successfully: \(postId)")
        } catch {
            print("❌ Failed to delete post: \(error)")
            errorMessage = "Failed to delete post: \(error.localizedDescription)"
            // Revert on error
            if let post = deletedRootPost, rootPost == nil {
                rootPost = post
            }
            if let post = deletedReply {
                replies.insert(post, at: 0)
            }
        }
    }
}
