import Foundation
import SwiftUI

@MainActor
final class TrendingFeedViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var trendingHashtags: [TrendingHashtag] = []
    @Published var selectedHashtag: TrendingHashtag?
    @Published var hashtagPosts: [Post] = []
    @Published var allTrendingPosts: [Post] = []
    @Published var isLoadingTrending = false
    @Published var isLoadingPosts = false
    @Published var isLoadingMore = false
    @Published var hasMorePosts = true
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let hashtagService: HashtagService
    private let feedService: FeedService
    private var postCursor: Date?
    private var refreshTimer: Timer?
    
    // MARK: - Initialization
    
    init(
        hashtagService: HashtagService = SupabaseHashtagService.shared,
        feedService: FeedService = SupabaseFeedService.shared
    ) {
        self.hashtagService = hashtagService
        self.feedService = feedService
    }
    
    // MARK: - Load Trending Hashtags
    
    func loadTrending(timeWindowHours: Int = 72, limit: Int = 10) async {
        isLoadingTrending = true
        errorMessage = nil
        defer { isLoadingTrending = false }
        
        do {
            trendingHashtags = try await hashtagService.getTrendingHashtags(
                timeWindowHours: timeWindowHours,
                limit: limit
            )
            print("✅ Loaded \(trendingHashtags.count) trending hashtags")
        } catch {
            errorMessage = "Failed to load trending: \(error.localizedDescription)"
            print("❌ Error loading trending: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Load All Trending Posts
    
    func loadAllTrendingPosts(timeWindowHours: Int = 72, limit: Int = 100) async {
        print("🔥 Fetching all trending posts, cursor: nil")
        isLoadingPosts = true
        errorMessage = nil
        defer { isLoadingPosts = false }
        
        do {
            let result = try await hashtagService.getAllTrendingPosts(
                timeWindowHours: timeWindowHours,
                cursor: nil,
                limit: limit
                
            )
            allTrendingPosts = result.posts
            print("✅ Loaded \(allTrendingPosts.count) trending posts, hasMore: \(result.hasMore)")
        } catch {
            errorMessage = "Failed to load trending posts: \(error.localizedDescription)"
            print("❌ Error loading trending posts: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Select Hashtag
    
    func selectHashtag(_ hashtag: TrendingHashtag) async {
        selectedHashtag = hashtag
        postCursor = nil
        hasMorePosts = true
        await loadPostsForSelectedHashtag()
    }
    
    // MARK: - Load Posts for Hashtag
    
    private func loadPostsForSelectedHashtag() async {
        guard let hashtag = selectedHashtag else { return }
        
        isLoadingPosts = true
        errorMessage = nil
        defer { isLoadingPosts = false }
        
        do {
            let result = try await hashtagService.getPostsByHashtag(
                tag: hashtag.tag,
                cursor: nil,
                limit: 20
            )
            
            hashtagPosts = result.posts
            hasMorePosts = result.hasMore
            
            // Store cursor for next page
            if let lastPost = result.posts.last {
                postCursor = lastPost.createdAt
            }
            
            print("✅ Loaded \(result.posts.count) posts for #\(hashtag.tag), hasMore: \(result.hasMore)")
        } catch {
            errorMessage = "Failed to load posts: \(error.localizedDescription)"
            print("❌ Error loading posts for hashtag: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Load More Posts
    
    func loadMorePosts() async {
        guard let hashtag = selectedHashtag,
              !isLoadingMore,
              hasMorePosts else {
            return
        }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            let result = try await hashtagService.getPostsByHashtag(
                tag: hashtag.tag,
                cursor: postCursor,
                limit: 20
            )
            
            hashtagPosts.append(contentsOf: result.posts)
            hasMorePosts = result.hasMore
            
            // Update cursor
            if let lastPost = result.posts.last {
                postCursor = lastPost.createdAt
            }
            
            print("✅ Loaded \(result.posts.count) more posts for #\(hashtag.tag), total: \(hashtagPosts.count)")
        } catch {
            print("❌ Error loading more posts: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Toggle Like
    
    func toggleLike(postId: String) async {
        // Check which array contains the post
        if let index = hashtagPosts.firstIndex(where: { $0.id == postId }) {
            await toggleLikeInHashtagPosts(postId: postId, index: index)
        } else if let index = allTrendingPosts.firstIndex(where: { $0.id == postId }) {
            await toggleLikeInAllTrendingPosts(postId: postId, index: index)
        }
    }
    
    private func toggleLikeInHashtagPosts(postId: String, index: Int) async {
        // Store original state
        let originalPost = hashtagPosts[index]
        let wasLiked = originalPost.isLiked
        
        // Optimistically update UI
        var updatedPost = Post(
            id: originalPost.id,
            text: originalPost.text,
            createdAt: originalPost.createdAt,
            author: originalPost.author,
            imageURLs: originalPost.imageURLs,
            videoURL: originalPost.videoURL,
            audioURL: originalPost.audioURL,
            likeCount: wasLiked ? max(0, originalPost.likeCount - 1) : originalPost.likeCount + 1,
            replyCount: originalPost.replyCount,
            isLiked: !wasLiked,
            parentPostId: originalPost.parentPostId,
            parentPost: originalPost.parentPost,
            leaderboardEntry: originalPost.leaderboardEntry,
            resharedPostId: originalPost.resharedPostId,
            spotifyLink: originalPost.spotifyLink,
            poll: originalPost.poll,
            backgroundMusic: originalPost.backgroundMusic
        )
        hashtagPosts[index] = updatedPost
        
        do {
            let newLikeState = try await feedService.toggleLike(postId: postId)
            // Verify state matches expectation
            if newLikeState != !wasLiked {
                // Correct if API returned different state
                updatedPost = Post(
                    id: originalPost.id,
                    text: originalPost.text,
                    createdAt: originalPost.createdAt,
                    author: originalPost.author,
                    imageURLs: originalPost.imageURLs,
                    videoURL: originalPost.videoURL,
                    audioURL: originalPost.audioURL,
                    likeCount: newLikeState ? originalPost.likeCount + 1 : max(0, originalPost.likeCount - 1),
                    replyCount: originalPost.replyCount,
                    isLiked: newLikeState,
                    parentPostId: originalPost.parentPostId,
                    parentPost: originalPost.parentPost,
                    leaderboardEntry: originalPost.leaderboardEntry,
                    resharedPostId: originalPost.resharedPostId,
                    spotifyLink: originalPost.spotifyLink,
                    poll: originalPost.poll,
                    backgroundMusic: originalPost.backgroundMusic
                )
                hashtagPosts[index] = updatedPost
            }
            print("✅ Like toggled for post \(postId), now liked: \(newLikeState)")
        } catch {
            print("Failed to toggle like: \(error)")
            // Revert on error
            hashtagPosts[index] = originalPost
        }
    }
    
    private func toggleLikeInAllTrendingPosts(postId: String, index: Int) async {
        // Store original state
        let originalPost = allTrendingPosts[index]
        let wasLiked = originalPost.isLiked
        
        // Optimistically update UI
        var updatedPost = Post(
            id: originalPost.id,
            text: originalPost.text,
            createdAt: originalPost.createdAt,
            author: originalPost.author,
            imageURLs: originalPost.imageURLs,
            videoURL: originalPost.videoURL,
            audioURL: originalPost.audioURL,
            likeCount: wasLiked ? max(0, originalPost.likeCount - 1) : originalPost.likeCount + 1,
            replyCount: originalPost.replyCount,
            isLiked: !wasLiked,
            parentPostId: originalPost.parentPostId,
            parentPost: originalPost.parentPost,
            leaderboardEntry: originalPost.leaderboardEntry,
            resharedPostId: originalPost.resharedPostId,
            spotifyLink: originalPost.spotifyLink,
            poll: originalPost.poll,
            backgroundMusic: originalPost.backgroundMusic
        )
        allTrendingPosts[index] = updatedPost
        
        do {
            let newLikeState = try await feedService.toggleLike(postId: postId)
            // Verify state matches expectation
            if newLikeState != !wasLiked {
                // Correct if API returned different state
                updatedPost = Post(
                    id: originalPost.id,
                    text: originalPost.text,
                    createdAt: originalPost.createdAt,
                    author: originalPost.author,
                    imageURLs: originalPost.imageURLs,
                    videoURL: originalPost.videoURL,
                    audioURL: originalPost.audioURL,
                    likeCount: newLikeState ? originalPost.likeCount + 1 : max(0, originalPost.likeCount - 1),
                    replyCount: originalPost.replyCount,
                    isLiked: newLikeState,
                    parentPostId: originalPost.parentPostId,
                    parentPost: originalPost.parentPost,
                    leaderboardEntry: originalPost.leaderboardEntry,
                    resharedPostId: originalPost.resharedPostId,
                    spotifyLink: originalPost.spotifyLink,
                    poll: originalPost.poll,
                    backgroundMusic: originalPost.backgroundMusic
                )
                allTrendingPosts[index] = updatedPost
            }
            print("✅ Like toggled for post \(postId), now liked: \(newLikeState)")
        } catch {
            print("Failed to toggle like: \(error)")
            // Revert on error
            allTrendingPosts[index] = originalPost
        }
    }
    
    // MARK: - Delete Post
    
    func deletePost(postId: String) async {
        // Optimistically remove from UI (both arrays)
        let deletedHashtagPost = hashtagPosts.first(where: { $0.id == postId })
        let deletedTrendingPost = allTrendingPosts.first(where: { $0.id == postId })
        hashtagPosts.removeAll { $0.id == postId }
        allTrendingPosts.removeAll { $0.id == postId }
        
        do {
            try await feedService.deletePost(postId: postId)
            print("✅ Post deleted successfully: \(postId)")
        } catch {
            errorMessage = "Failed to delete post: \(error.localizedDescription)"
            print("❌ Failed to delete post: \(error)")
            // Revert optimistic delete on error
            if let post = deletedHashtagPost {
                hashtagPosts.insert(post, at: 0)
            }
            if let post = deletedTrendingPost {
                allTrendingPosts.insert(post, at: 0)
            }
        }
    }
    
    // MARK: - Refresh
    
    func refresh() async {
        await loadTrending()
        await loadAllTrendingPosts()
        if selectedHashtag != nil {
            postCursor = nil
            hasMorePosts = true
            await loadPostsForSelectedHashtag()
        }
    }
    
    // MARK: - Auto Refresh
    
    /// Starts automatic refresh of trending content
    /// - Parameter interval: Time interval between refreshes in seconds (default: 300 = 5 minutes)
    func startAutoRefresh(interval: TimeInterval = 300) {
        stopAutoRefresh() // Stop any existing timer
        
        print("🔄 Starting auto-refresh for trending (interval: \(Int(interval))s)")
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                print("🔄 Auto-refreshing trending content...")
                await self.refresh()
            }
        }
    }
    
    /// Stops automatic refresh
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("⏸️ Stopped auto-refresh for trending")
    }
}

