import Foundation
import SwiftUI

@MainActor
final class UserProfileViewModel: ObservableObject {
    enum Section: String, CaseIterable {
        case posts = "Posts"
        case replies = "Replies"
        case likes = "Likes"
        case mutuals = "Mutuals"
        // Note: followers and following are removed from tabs but still exist as orphaned cases
        // for backward compatibility. Access followers/following via stats buttons instead.
        case followers = "Followers"
        case following = "Following"
    }
    
    @Published var user: UserSummary?
    @Published var posts: [Post] = []
    @Published var likedPosts: [Post] = []
    @Published var followers: [UserSummary] = []
    @Published var following: [UserSummary] = []
    @Published var mutuals: [UserSummary] = []
    @Published var selectedSection: Section = .posts
    @Published var isPostNotificationsOn: Bool = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let userId: String
    private let social: SocialGraphService
    private let feed: FeedService
    
    init(
        userId: String,
        social: SocialGraphService = SupabaseSocialGraphService.shared,
        feed: FeedService = SupabaseFeedService.shared
    ) {
        self.userId = userId
        self.social = social
        self.feed = feed
    }
    
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            // Load profile
            let profile = try await social.getProfile(userId: userId)
            await MainActor.run {
                self.user = profile
            }
            
            // Load followers, following, and mutuals
            async let followersTask = social.getFollowers(of: userId)
            async let followingTask = social.getFollowing(of: userId)
            async let mutualsTask = social.getMutuals(with: userId)
            
            let (followersResult, followingResult, mutualsResult) = try await (followersTask, followingTask, mutualsTask)
            
            await MainActor.run {
                self.followers = followersResult
                self.following = followingResult
                self.mutuals = mutualsResult
            }
            
            // Load posts, replies, and liked posts
            async let postsTask = feed.fetchPostsByUser(userId)
            async let repliesTask = feed.fetchRepliesByUser(userId)
            async let likedPostsTask = feed.fetchLikedPostsByUser(userId)
            
            let (postsResult, repliesResult, likedPostsResult) = try await (postsTask, repliesTask, likedPostsTask)
            
            await MainActor.run {
                // Combine posts and replies for display
                self.posts = postsResult + repliesResult
                self.likedPosts = likedPostsResult
            }
            
            // Load post notifications setting if following
            if profile.isFollowing {
                await loadPostNotificationsSetting()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func loadPostNotificationsSetting() async {
        // Check if notify_on_posts is enabled for this user
        // This would require a new method in SocialGraphService or direct query
        // For now, we'll set it to false and update it when user toggles
        // You may want to add a method like getPostNotificationsSetting(for:) to SocialGraphService
    }
    
    func toggleFollow() async {
        guard let user = user else { return }
        
        do {
            if user.isFollowing {
                try await social.unfollow(userId: user.id)
            } else {
                try await social.follow(userId: user.id)
            }
            // Reload to get updated counts and follow status
            await load()
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    func togglePostNotifications() async {
        guard let user = user else { return }
        
        do {
            let newValue = !isPostNotificationsOn
            try await social.setPostNotifications(for: user.id, enabled: newValue)
            await MainActor.run {
                self.isPostNotificationsOn = newValue
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    var followerCount: Int {
        user?.followersCount ?? 0
    }
    
    var followingCount: Int {
        user?.followingCount ?? 0
    }
    
    func toggleLike(postId: String) async {
        // Store original posts for potential revert
        let originalPosts = posts
        let originalLikedPosts = likedPosts
        
        // Update local state optimistically
        if let index = posts.firstIndex(where: { $0.id == postId }) {
            let originalPost = posts[index]
            let wasLiked = originalPost.isLiked
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
                parentPostId: originalPost.parentPostId,
                parentPost: originalPost.parentPost,
                leaderboardEntry: originalPost.leaderboardEntry,
                resharedPostId: originalPost.resharedPostId,
                spotifyLink: originalPost.spotifyLink,
                poll: originalPost.poll,
                backgroundMusic: originalPost.backgroundMusic
            )
            posts[index] = updatedPost
        }
        
        // Also update in likedPosts if present
        if let index = likedPosts.firstIndex(where: { $0.id == postId }) {
            let originalPost = likedPosts[index]
            let wasLiked = originalPost.isLiked
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
                parentPostId: originalPost.parentPostId,
                parentPost: originalPost.parentPost,
                leaderboardEntry: originalPost.leaderboardEntry,
                resharedPostId: originalPost.resharedPostId,
                spotifyLink: originalPost.spotifyLink,
                poll: originalPost.poll,
                backgroundMusic: originalPost.backgroundMusic
            )
            likedPosts[index] = updatedPost
        }
        
        // Call service to update on server
        do {
            try await feed.toggleLike(postId: postId)
        } catch {
            // Revert on error
            await MainActor.run {
                self.posts = originalPosts
                self.likedPosts = originalLikedPosts
            }
        }
    }
    
    func deletePost(postId: String) async {
        do {
            try await feed.deletePost(postId: postId)
            // Remove from local arrays
            posts.removeAll { $0.id == postId }
            likedPosts.removeAll { $0.id == postId }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
