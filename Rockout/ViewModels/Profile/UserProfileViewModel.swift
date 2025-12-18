import Foundation
import SwiftUI

@MainActor
final class UserProfileViewModel: ObservableObject {
    enum Section: String, CaseIterable {
        case bars = "Bars"
        case adlibs = "Adlibs"
        case amps = "Amps"
        case echoes = "Echoes"
        case mutuals = "Mutuals"
        // Note: followers and following are removed from tabs but still exist as orphaned cases
        // for backward compatibility. Access followers/following via stats buttons instead.
        case followers = "Followers"
        case following = "Following"
    }
    
    @Published var user: UserSummary?
    @Published var posts: [Post] = []
    @Published var replies: [Post] = []
    @Published var likedPosts: [Post] = []
    @Published var echoedPosts: [Post] = []
    @Published var followers: [UserSummary] = []
    @Published var following: [UserSummary] = []
    @Published var mutuals: [UserSummary] = []
    @Published var selectedSection: Section = .bars
    @Published var isPostNotificationsOn: Bool = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let userId: String
    private let social: SocialGraphService
    private let feed: FeedService
    
    init(
        userId: String,
        initialUser: UserSummary? = nil,
        social: SocialGraphService = SupabaseSocialGraphService.shared,
        feed: FeedService = SupabaseFeedService.shared
    ) {
        self.userId = userId
        self.social = social
        self.feed = feed
        // Set initial user for immediate display
        if let initialUser = initialUser {
            self.user = initialUser
        }
    }
    
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            // Load profile (this will have complete data including social handles and counts)
            let profile = try await social.getProfile(userId: userId)
            await MainActor.run {
                // Update with fresh data from database
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
            
            // Load posts, replies, liked posts, and echoed posts
            async let postsTask = feed.fetchPostsByUser(userId)
            async let repliesTask = feed.fetchRepliesByUser(userId)
            async let likedPostsTask = feed.fetchLikedPostsByUser(userId)
            async let echoedPostsTask = feed.fetchEchoedPostsByUser(userId)
            
            let (postsResult, repliesResult, likedPostsResult, echoedPostsResult) = try await (postsTask, repliesTask, likedPostsTask, echoedPostsTask)
            
            print("📊 Profile data loaded for user \(userId):")
            print("  - Posts (Bars): \(postsResult.count)")
            print("  - Replies (Adlibs): \(repliesResult.count)")
            print("  - Liked Posts (Amps): \(likedPostsResult.count)")
            print("  - Echoed Posts (Echoes): \(echoedPostsResult.count)")
            
            await MainActor.run {
                // Bars: Only original posts (no replies, no echoes)
                self.posts = postsResult.filter { $0.resharedPostId == nil }
                // Adlibs: Only replies (posts with parent_post_id)
                self.replies = repliesResult
                // Amps: Posts liked by this user
                self.likedPosts = likedPostsResult
                // Echoes: Posts echoed by this user
                self.echoedPosts = echoedPostsResult
                
                print("📊 Profile data set in view model:")
                print("  - Posts (Bars): \(self.posts.count)")
                print("  - Replies (Adlibs): \(self.replies.count)")
                print("  - Liked Posts (Amps): \(self.likedPosts.count)")
                print("  - Echoed Posts (Echoes): \(self.echoedPosts.count)")
            }
            
            // Load post notifications setting if following
            if profile.isFollowing {
                await loadPostNotificationsSetting()
            }
        } catch {
            print("❌ Error loading profile data for user \(userId): \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ Error userInfo: \(nsError.userInfo)")
            }
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
        guard var user = user else { return }
        
        // Store original state for potential revert
        let originalIsFollowing = user.isFollowing
        let originalFollowersCount = user.followersCount
        
        // Optimistically update UI immediately
        await MainActor.run {
            self.user = UserSummary(
                id: user.id,
                displayName: user.displayName,
                handle: user.handle,
                avatarInitials: user.avatarInitials,
                profilePictureURL: user.profilePictureURL,
                isFollowing: !originalIsFollowing,
                region: user.region,
                followersCount: originalIsFollowing ? max(0, originalFollowersCount - 1) : originalFollowersCount + 1,
                followingCount: user.followingCount,
                instagramHandle: user.instagramHandle,
                twitterHandle: user.twitterHandle,
                tiktokHandle: user.tiktokHandle
            )
        }
        
        // Perform API call
        do {
            if originalIsFollowing {
                try await social.unfollow(userId: user.id)
            } else {
                try await social.follow(userId: user.id)
            }
            // Small delay to ensure database transaction completes before reloading
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds - increased to ensure DB commit
            
            // Force refresh by reloading - getProfile() will fetch fresh isFollowing state
            await load()
        } catch {
            // Revert optimistic update on error
            await MainActor.run {
                self.user = UserSummary(
                    id: user.id,
                    displayName: user.displayName,
                    handle: user.handle,
                    avatarInitials: user.avatarInitials,
                    profilePictureURL: user.profilePictureURL,
                    isFollowing: originalIsFollowing,
                    region: user.region,
                    followersCount: originalFollowersCount,
                    followingCount: user.followingCount,
                    instagramHandle: user.instagramHandle,
                    twitterHandle: user.twitterHandle,
                    tiktokHandle: user.tiktokHandle
                )
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
    
    func toggleEcho(postId: String) async {
        // Store original posts for potential revert
        let originalPosts = posts
        let originalEchoedPosts = echoedPosts
        
        // Update local state optimistically
        if let index = posts.firstIndex(where: { $0.id == postId }) {
            let originalPost = posts[index]
            let wasEchoed = originalPost.isEchoed
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
                backgroundMusic: originalPost.backgroundMusic
            )
            posts[index] = updatedPost
        }
        
        // Also update in echoedPosts if present
        if let index = echoedPosts.firstIndex(where: { $0.id == postId }) {
            let originalPost = echoedPosts[index]
            let wasEchoed = originalPost.isEchoed
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
                backgroundMusic: originalPost.backgroundMusic
            )
            echoedPosts[index] = updatedPost
        }
        
        // Call service to update on server
        do {
            try await feed.toggleEcho(postId: postId)
        } catch {
            // Revert on error
            await MainActor.run {
                self.posts = originalPosts
                self.echoedPosts = originalEchoedPosts
            }
        }
    }
    
    func deletePost(postId: String) async {
        do {
            try await feed.deletePost(postId: postId)
            // Remove from local arrays
            posts.removeAll { $0.id == postId }
            likedPosts.removeAll { $0.id == postId }
            echoedPosts.removeAll { $0.id == postId }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
