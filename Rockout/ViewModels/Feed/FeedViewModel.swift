import Foundation
import SwiftUI
import Combine
import Supabase

@MainActor
final class FeedViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMorePages = true
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    let service: FeedService
    private let feedStore = FeedStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentFeedType: FeedType = .forYou
    private var cursors: [FeedType: Date] = [:] // Track cursor per feed type
    
    // MARK: - Initialization
    
    init(service: FeedService = SupabaseFeedService.shared) {
        self.service = service
        
        // Subscribe to FeedStore changes
        feedStore.$posts
            .sink { [weak self] _ in
                self?.updatePostsFromStore()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Update Posts from Store
    
    private func updatePostsFromStore() {
        Task {
            await filterPostsFromStore()
        }
    }
    
    private func filterPostsFromStore() async {
        // Get posts for the current feed type
        let cachedPosts = feedStore.getPostsForFeed(currentFeedType)
        
        // Update posts (already filtered and ordered by FeedStore)
        self.posts = cachedPosts
    }
    
    private func getCurrentUser() async -> UserSummary {
        // Get current user from service
        if let currentUserId = SupabaseService.shared.client.auth.currentUser?.id.uuidString {
            let social = SupabaseSocialGraphService.shared
            let allUsers = await social.allUsers()
            return allUsers.first(where: { $0.id == currentUserId }) ?? UserSummary(
                id: currentUserId,
                displayName: "User",
                handle: "@user",
                avatarInitials: "U",
                profilePictureURL: nil,
                isFollowing: false
            )
        }
        return UserSummary(
            id: "demo-user",
            displayName: "User",
            handle: "@user",
            avatarInitials: "U",
            profilePictureURL: nil,
            isFollowing: false
        )
    }
    
    // MARK: - Load Feed
    
    func load(feedType: FeedType = .forYou, region: String? = nil) async {
        isLoading = true
        errorMessage = nil
        currentFeedType = feedType
        cursors[feedType] = nil // Reset cursor for fresh load
        hasMorePages = true
        defer { isLoading = false }
        
        do {
            // Check if we have cached posts for this feed type
            let cachedPosts = feedStore.getPostsForFeed(feedType)
            if !cachedPosts.isEmpty {
                // Use cached posts for instant display
                posts = cachedPosts
                print("✅ Using \(cachedPosts.count) cached posts for \(feedType.rawValue)")
            }
            
            // Fetch fresh data
            let result = try await (service as! SupabaseFeedService).fetchHomeFeed(
                feedType: feedType,
                region: region,
                cursor: nil,
                limit: 20
            )
            
            // Replace cached posts with fresh data
            feedStore.replacePosts(result.posts, for: feedType)
            posts = result.posts
            hasMorePages = result.hasMore
            
            // Store cursor (last post's createdAt) for next page
            if let lastPost = result.posts.last {
                cursors[feedType] = lastPost.createdAt
            }
            
            print("✅ Loaded \(result.posts.count) fresh posts for \(feedType.rawValue), hasMore: \(result.hasMore)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading feed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Load More (Pagination)
    
    func loadMore(feedType: FeedType = .forYou, region: String? = nil) async {
        guard !isLoadingMore && hasMorePages else {
            print("⚠️ Skipping loadMore: isLoadingMore=\(isLoadingMore), hasMorePages=\(hasMorePages)")
            return
        }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            let cursor = cursors[feedType]
            print("🔍 Loading more posts with cursor: \(cursor?.description ?? "nil")")
            
            let result = try await (service as! SupabaseFeedService).fetchHomeFeed(
                feedType: feedType,
                region: region,
                cursor: cursor,
                limit: 20
            )
            
            // Append new posts to FeedStore
            feedStore.appendPosts(result.posts, for: feedType)
            posts.append(contentsOf: result.posts)
            hasMorePages = result.hasMore
            
            // Update cursor
            if let lastPost = result.posts.last {
                cursors[feedType] = lastPost.createdAt
            }
            
            print("✅ Loaded \(result.posts.count) more posts, total: \(posts.count), hasMore: \(result.hasMore)")
        } catch {
            print("❌ Error loading more posts: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Refresh
    
    func refresh(feedType: FeedType = .forYou, region: String? = nil) async {
        // Reload the feed (this will fetch fresh data and update the cache)
        await load(feedType: feedType, region: region)
    }
    
    // MARK: - Create Post
    
    func createPost(text: String, imageURLs: [URL] = [], videoURL: URL? = nil, audioURL: URL? = nil, leaderboardEntry: LeaderboardEntrySummary?, mentionedUserIds: [String] = []) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageURLs.isEmpty || videoURL != nil || audioURL != nil else {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            _ = try await service.createPost(text: text, imageURLs: imageURLs, videoURL: videoURL, audioURL: audioURL, leaderboardEntry: leaderboardEntry, spotifyLink: nil, poll: nil, backgroundMusic: nil, mentionedUserIds: mentionedUserIds)
            // FeedStore will update automatically, no need to reload
        } catch {
            errorMessage = "Failed to create post: \(error.localizedDescription)"
        }
    }
    
    func deletePost(postId: String) async {
        // Optimistically remove from UI
        let deletedPost = posts.first(where: { $0.id == postId })
        posts.removeAll { $0.id == postId }
        
        do {
            try await service.deletePost(postId: postId)
            print("✅ Post deleted successfully: \(postId)")
        } catch {
            errorMessage = "Failed to delete post: \(error.localizedDescription)"
            print("❌ Failed to delete post: \(error)")
            // Revert optimistic delete on error
            if let post = deletedPost {
                posts.insert(post, at: 0)
            }
        }
    }
    
    // MARK: - Reply to Post
    
    func reply(to parentPost: Post, text: String, imageURLs: [URL] = [], videoURL: URL? = nil, audioURL: URL? = nil, mentionedUserIds: [String] = []) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageURLs.isEmpty || videoURL != nil || audioURL != nil else {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            _ = try await service.reply(to: parentPost, text: text, imageURLs: imageURLs, videoURL: videoURL, audioURL: audioURL, spotifyLink: nil, poll: nil, backgroundMusic: nil, mentionedUserIds: mentionedUserIds)
            // Note: Replies appear in thread view, not feed
        } catch {
            errorMessage = "Failed to reply: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Create Leaderboard Comment
    
    func createLeaderboardComment(entry: LeaderboardEntrySummary, text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            _ = try await service.createLeaderboardComment(entry: entry, text: text)
            // FeedStore will update automatically, no need to reload
        } catch {
            errorMessage = "Failed to create comment: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Toggle Echo
    
    func toggleEcho(postId: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else {
            return
        }
        
        // Store original post
        let originalPost = posts[index]
        let wasEchoed = originalPost.isEchoed
        
        // Optimistically update UI
        let updatedPost = Post(
            id: originalPost.id,
            text: originalPost.text,
            createdAt: originalPost.createdAt,
            author: originalPost.author,
            imageURLs: originalPost.imageURLs,
            videoURL: originalPost.videoURL,
            audioURL: originalPost.audioURL,
            likeCount: originalPost.likeCount,
            replyCount: originalPost.replyCount,
            isLiked: originalPost.isLiked,
            echoCount: wasEchoed ? max(0, originalPost.echoCount - 1) : originalPost.echoCount + 1,
            isEchoed: !wasEchoed,
            parentPostId: originalPost.parentPostId,
            parentPost: originalPost.parentPost,
            leaderboardEntry: originalPost.leaderboardEntry,
            resharedPostId: originalPost.resharedPostId,
            spotifyLink: originalPost.spotifyLink,
            poll: originalPost.poll,
            backgroundMusic: originalPost.backgroundMusic,
            mentionedUserIds: originalPost.mentionedUserIds
        )
        posts[index] = updatedPost
        
        do {
            let newEchoState = try await service.toggleEcho(postId: postId)
            print("✅ Echo toggled for post \(postId), now echoed: \(newEchoState)")
            
            // Refresh the feed to get updated echo count
            await load(feedType: currentFeedType)
        } catch {
            errorMessage = "Failed to echo post: \(error.localizedDescription)"
            // Revert optimistic update
            posts[index] = originalPost
        }
    }
    
    // MARK: - Toggle Like
    
    func toggleLike(postId: String) async {
        guard let index = posts.firstIndex(where: { $0.id == postId }) else {
            return
        }
        
        // Store original post
        let originalPost = posts[index]
        let wasLiked = originalPost.isLiked
        
        // Optimistically update UI
        let updatedPost = Post(
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
            echoCount: originalPost.echoCount,
            isEchoed: originalPost.isEchoed,
            parentPostId: originalPost.parentPostId,
            parentPost: originalPost.parentPost,
            leaderboardEntry: originalPost.leaderboardEntry,
            resharedPostId: originalPost.resharedPostId,
            spotifyLink: originalPost.spotifyLink,
            poll: originalPost.poll,
            backgroundMusic: originalPost.backgroundMusic
        )
        posts[index] = updatedPost
        
        do {
            let newLikeState = try await service.toggleLike(postId: postId)
            print("✅ Like toggled for post \(postId), now liked: \(newLikeState)")
            
            // Verify the state matches what we expected
            if newLikeState != !wasLiked {
                // If API returned different state, update again
                let correctedPost = Post(
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
                    echoCount: originalPost.echoCount,
                    isEchoed: originalPost.isEchoed,
                    parentPostId: originalPost.parentPostId,
                    parentPost: originalPost.parentPost,
                    leaderboardEntry: originalPost.leaderboardEntry,
                    resharedPostId: originalPost.resharedPostId,
                    spotifyLink: originalPost.spotifyLink,
                    poll: originalPost.poll,
                    backgroundMusic: originalPost.backgroundMusic
                )
                posts[index] = correctedPost
            }
        } catch {
            print("Failed to toggle like: \(error)")
            // Revert optimistic update on error
            posts[index] = originalPost
        }
    }
    
    // MARK: - Load User Posts
    
    func loadUserPosts(userId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        print("🔍 FeedViewModel.loadUserPosts called for userId: \(userId)")
        do {
            let fetchedPosts = try await service.fetchPostsByUser(userId)
            // Filter out echoed posts - Bars tab should only show original posts
            posts = fetchedPosts.filter { $0.resharedPostId == nil }
            print("✅ FeedViewModel.loadUserPosts: Set \(posts.count) posts for user \(userId) (filtered out echoes)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading user posts: \(error.localizedDescription)")
        }
    }
    
    func loadUserReplies(userId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            posts = try await service.fetchRepliesByUser(userId)
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading user replies: \(error.localizedDescription)")
        }
    }
    
    func loadUserLikedPosts(userId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            posts = try await service.fetchLikedPostsByUser(userId)
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading user liked posts: \(error.localizedDescription)")
        }
    }
    
    func loadUserEchoedPosts(userId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            posts = try await service.fetchEchoedPostsByUser(userId)
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading user echoed posts: \(error.localizedDescription)")
        }
    }
}
