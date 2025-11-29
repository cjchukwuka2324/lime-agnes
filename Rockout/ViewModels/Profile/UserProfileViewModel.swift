import Foundation
import SwiftUI

@MainActor
final class UserProfileViewModel: ObservableObject {
    enum Section: String, CaseIterable {
        case posts = "Posts"
        case replies = "Replies"
        case likes = "Likes"
        case followers = "Followers"
        case following = "Following"
        case mutuals = "Mutuals"
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
            
            // Load posts and liked posts
            async let postsTask = feed.fetchPostsByUser(userId)
            async let likedPostsTask = feed.fetchLikedPostsByUser(userId)
            
            let (postsResult, likedPostsResult) = try await (postsTask, likedPostsTask)
            
            await MainActor.run {
                self.posts = postsResult
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
}
