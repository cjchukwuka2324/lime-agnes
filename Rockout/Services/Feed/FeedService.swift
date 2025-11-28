import Foundation
import Supabase

// MARK: - Feed Type

enum FeedType {
    case forYou  // Region-based feed
    case following  // Users you follow
}

// MARK: - FeedService Protocol

protocol FeedService {
    func fetchHomeFeed(feedType: FeedType, region: String?) async throws -> [Post]
    func fetchThread(for postId: String) async throws -> (root: Post, replies: [Post])
    func fetchReplies(for postId: String) async throws -> [Post]
    
    func createPost(
        text: String,
        imageURL: URL?,
        videoURL: URL?,
        audioURL: URL?,
        leaderboardEntry: LeaderboardEntrySummary?
    ) async throws -> Post
    
    func reply(
        to parentPost: Post,
        text: String,
        imageURL: URL?,
        videoURL: URL?,
        audioURL: URL?
    ) async throws -> Post
    
    func createLeaderboardComment(
        entry: LeaderboardEntrySummary,
        text: String
    ) async throws -> Post
    
    func likePost(_ postId: String) async throws -> Post
    func unlikePost(_ postId: String) async throws -> Post
    func fetchPostsByUser(_ userId: String) async throws -> [Post]
    func fetchRepliesByUser(_ userId: String) async throws -> [Post]
    func fetchLikedPostsByUser(_ userId: String) async throws -> [Post]
}

// MARK: - In-Memory Implementation for MVP

final class InMemoryFeedService: FeedService {
    static let shared = InMemoryFeedService()
    
    private var posts: [Post] = []
    private let queue = DispatchQueue(label: "FeedServiceQueue", qos: .userInitiated)
    private let profileService = UserProfileService.shared
    
    private init() {
        seedDemoData()
    }
    
    // MARK: - Current User Helper
    
    private func currentUserSummary() async -> UserSummary {
        // Try to get real user profile
        if let profile = try? await profileService.getCurrentUserProfile() {
            let displayName: String
            if let firstName = profile.firstName, let lastName = profile.lastName {
                displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            } else if let displayNameValue = profile.displayName, !displayNameValue.isEmpty {
                displayName = displayNameValue
            } else {
                // Fallback to email
                let email = SupabaseService.shared.client.auth.currentUser?.email ?? "User"
                displayName = email.components(separatedBy: "@").first ?? "User"
            }
            
            // Generate handle from username, email, or first name
            let handle: String
            if let username = profile.username {
                handle = "@\(username)"
            } else if let email = SupabaseService.shared.client.auth.currentUser?.email {
                let emailPrefix = email.components(separatedBy: "@").first ?? "user"
                handle = "@\(emailPrefix)"
            } else if let firstName = profile.firstName {
                handle = "@\(firstName.lowercased())"
            } else {
                handle = "@user"
            }
            
            // Generate avatar initials
            let initials: String
            if let firstName = profile.firstName, let lastName = profile.lastName {
                let firstInitial = String(firstName.prefix(1)).uppercased()
                let lastInitial = String(lastName.prefix(1)).uppercased()
                initials = "\(firstInitial)\(lastInitial)"
            } else {
                initials = String(displayName.prefix(2)).uppercased()
            }
            
            // Get profile picture URL if available
            let pictureURL: URL? = {
                if let pictureURLString = profile.profilePictureURL, let url = URL(string: pictureURLString) {
                    return url
                }
                return nil
            }()
            
            return UserSummary(
                id: profile.id.uuidString,
                displayName: displayName,
                handle: handle,
                avatarInitials: initials,
                profilePictureURL: pictureURL
            )
        }
        
        // Fallback to demo user if no profile found
        return currentDemoUser()
    }
    
    func fetchHomeFeed(feedType: FeedType, region: String?) async throws -> [Post] {
        // Refresh current user's profile data in all existing posts
        await refreshCurrentUserProfileInPosts()
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // Include both root posts and replies in the timeline
                var filtered = self.posts
                
                // Filter by feed type
                switch feedType {
                case .forYou:
                    // For "For You", return all posts (region filtering can be added later)
                    break
                case .following:
                    // For "Following", filter by users you follow
                    // This is a simplified version - in production, you'd query the follow relationships
                    // For now, we'll return all posts (can be enhanced with real follow data)
                    break
                }
                
                let sorted = filtered.sorted(by: { $0.createdAt > $1.createdAt })
                continuation.resume(returning: sorted)
            }
        }
    }
    
    func fetchThread(for postId: String) async throws -> (root: Post, replies: [Post]) {
        // Refresh current user's profile data in all existing posts
        await refreshCurrentUserProfileInPosts()
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let root = self.posts.first(where: { $0.id == postId }) else {
                    continuation.resume(throwing: NSError(
                        domain: "FeedService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Post not found"]
                    ))
                    return
                }
                
                let replies = self.posts
                    .filter { $0.parentPostId == postId }
                    .sorted(by: { $0.createdAt < $1.createdAt })
                
                continuation.resume(returning: (root, replies))
            }
        }
    }
    
    func createPost(
        text: String,
        imageURL: URL?,
        videoURL: URL?,
        audioURL: URL?,
        leaderboardEntry: LeaderboardEntrySummary?
    ) async throws -> Post {
        let author = await currentUserSummary()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let post = Post(
                    id: UUID().uuidString,
                    author: author,
                    text: text,
                    createdAt: Date(),
                    imageURL: imageURL,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    parentPostId: nil,
                    parentPostSummary: nil,
                    leaderboardEntry: leaderboardEntry,
                    resharedPostId: nil,
                    likeCount: 0,
                    isLiked: false,
                    replyCount: 0
                )
                self.posts.append(post)
                continuation.resume(returning: post)
            }
        }
    }
    
    func reply(to parentPost: Post, text: String, imageURL: URL?, videoURL: URL?, audioURL: URL?) async throws -> Post {
        let author = await currentUserSummary()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // Create parent post summary for timeline display
                let parentSummary = PostSummary(
                    id: parentPost.id,
                    author: parentPost.author,
                    text: parentPost.text,
                    imageURL: parentPost.imageURL,
                    videoURL: parentPost.videoURL,
                    audioURL: parentPost.audioURL
                )
                
                let reply = Post(
                    id: UUID().uuidString,
                    author: author,
                    text: text,
                    createdAt: Date(),
                    imageURL: imageURL,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    parentPostId: parentPost.id,
                    parentPostSummary: parentSummary,
                    leaderboardEntry: parentPost.leaderboardEntry,
                    resharedPostId: nil,
                    likeCount: 0,
                    isLiked: false,
                    replyCount: 0
                )
                self.posts.append(reply)
                
                // Update parent post reply count
                if let parentIndex = self.posts.firstIndex(where: { $0.id == parentPost.id }) {
                    var updatedParent = self.posts[parentIndex]
                    updatedParent = Post(
                        id: updatedParent.id,
                        author: updatedParent.author,
                        text: updatedParent.text,
                        createdAt: updatedParent.createdAt,
                        imageURL: updatedParent.imageURL,
                        videoURL: updatedParent.videoURL,
                        audioURL: updatedParent.audioURL,
                        parentPostId: updatedParent.parentPostId,
                        parentPostSummary: updatedParent.parentPostSummary,
                        leaderboardEntry: updatedParent.leaderboardEntry,
                        resharedPostId: updatedParent.resharedPostId,
                        likeCount: updatedParent.likeCount,
                        isLiked: updatedParent.isLiked,
                        replyCount: updatedParent.replyCount + 1
                    )
                    self.posts[parentIndex] = updatedParent
                    
                    // Create notification for reply (if not replying to own post)
                    if updatedParent.author.id != author.id {
                        Task { @MainActor in
                            NotificationService.shared.createReplyNotification(from: author, for: updatedParent)
                        }
                    }
                }
                
                continuation.resume(returning: reply)
            }
        }
    }
    
    func createLeaderboardComment(
        entry: LeaderboardEntrySummary,
        text: String
    ) async throws -> Post {
        try await createPost(text: text, imageURL: nil, videoURL: nil, audioURL: nil, leaderboardEntry: entry)
    }
    
    func fetchReplies(for postId: String) async throws -> [Post] {
        // Refresh current user's profile data in all existing posts
        await refreshCurrentUserProfileInPosts()
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let replies = self.posts
                    .filter { $0.parentPostId == postId }
                    .sorted(by: { $0.createdAt < $1.createdAt })
                continuation.resume(returning: replies)
            }
        }
    }
    
    func likePost(_ postId: String) async throws -> Post {
        // Get current user before entering queue
        let currentUser = await currentUserSummary()
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let index = self.posts.firstIndex(where: { $0.id == postId }) else {
                    continuation.resume(throwing: NSError(
                        domain: "FeedService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Post not found"]
                    ))
                    return
                }
                
                var post = self.posts[index]
                if !post.isLiked {
                    post = Post(
                        id: post.id,
                        author: post.author,
                        text: post.text,
                        createdAt: post.createdAt,
                        imageURL: post.imageURL,
                        videoURL: post.videoURL,
                        audioURL: post.audioURL,
                        parentPostId: post.parentPostId,
                        parentPostSummary: post.parentPostSummary,
                        leaderboardEntry: post.leaderboardEntry,
                        resharedPostId: post.resharedPostId,
                        likeCount: post.likeCount + 1,
                        isLiked: true,
                        replyCount: post.replyCount
                    )
                    self.posts[index] = post
                    
                    // Create notification for like (if not liking own post)
                    if post.author.id != currentUser.id {
                        Task { @MainActor in
                            NotificationService.shared.createLikeNotification(from: currentUser, for: post)
                        }
                    }
                }
                continuation.resume(returning: post)
            }
        }
    }
    
    func unlikePost(_ postId: String) async throws -> Post {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let index = self.posts.firstIndex(where: { $0.id == postId }) else {
                    continuation.resume(throwing: NSError(
                        domain: "FeedService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Post not found"]
                    ))
                    return
                }
                
                var post = self.posts[index]
                if post.isLiked {
                    post = Post(
                        id: post.id,
                        author: post.author,
                        text: post.text,
                        createdAt: post.createdAt,
                        imageURL: post.imageURL,
                        videoURL: post.videoURL,
                        audioURL: post.audioURL,
                        parentPostId: post.parentPostId,
                        parentPostSummary: post.parentPostSummary,
                        leaderboardEntry: post.leaderboardEntry,
                        resharedPostId: post.resharedPostId,
                        likeCount: max(0, post.likeCount - 1),
                        isLiked: false,
                        replyCount: post.replyCount
                    )
                    self.posts[index] = post
                }
                continuation.resume(returning: post)
            }
        }
    }
    
    // MARK: - Demo Data
    
    private func seedDemoData() {
        // Seed data will be created dynamically when users create posts
        // No need for demo data since we're using real user profiles
        self.posts = []
    }
    
    private func currentDemoUser() -> UserSummary {
        // Fallback demo user if profile can't be loaded
        // This should rarely be used since we try to get real profile first
        UserSummary(
            id: "demo-user",
            displayName: "User",
            handle: "@user",
            avatarInitials: "U",
            profilePictureURL: nil
        )
    }
    
    // MARK: - Refresh Current User Profile in Posts
    
    /// Updates all posts by the current user with fresh profile data (including profile picture)
    private func refreshCurrentUserProfileInPosts() async {
        // Get fresh current user summary with latest profile picture
        let freshUserSummary = await currentUserSummary()
        let currentUserId = freshUserSummary.id
        
        // Update all posts where author is current user
        await withCheckedContinuation { continuation in
            queue.async {
                for index in self.posts.indices {
                    if self.posts[index].author.id == currentUserId {
                        // Update post with fresh user summary
                        var updatedPost = self.posts[index]
                        updatedPost = Post(
                            id: updatedPost.id,
                            author: freshUserSummary, // Use fresh user summary with latest profile picture
                            text: updatedPost.text,
                            createdAt: updatedPost.createdAt,
                            imageURL: updatedPost.imageURL,
                            videoURL: updatedPost.videoURL,
                            audioURL: updatedPost.audioURL,
                            parentPostId: updatedPost.parentPostId,
                            parentPostSummary: updatedPost.parentPostSummary,
                            leaderboardEntry: updatedPost.leaderboardEntry,
                            resharedPostId: updatedPost.resharedPostId,
                            likeCount: updatedPost.likeCount,
                            isLiked: updatedPost.isLiked,
                            replyCount: updatedPost.replyCount
                        )
                        self.posts[index] = updatedPost
                    }
                }
                continuation.resume()
            }
        }
    }
    
    func fetchPostsByUser(_ userId: String) async throws -> [Post] {
        // Refresh current user's profile data if fetching current user's posts
        if let currentUserId = SupabaseService.shared.client.auth.currentUser?.id.uuidString,
           userId == currentUserId {
            await refreshCurrentUserProfileInPosts()
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let userPosts = self.posts
                    .filter { $0.author.id == userId && $0.parentPostId == nil } // Only root posts, no replies
                    .sorted(by: { $0.createdAt > $1.createdAt }) // Most recent first
                continuation.resume(returning: userPosts)
            }
        }
    }
    
    func fetchRepliesByUser(_ userId: String) async throws -> [Post] {
        // Refresh current user's profile data if fetching current user's replies
        if let currentUserId = SupabaseService.shared.client.auth.currentUser?.id.uuidString,
           userId == currentUserId {
            await refreshCurrentUserProfileInPosts()
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let userReplies = self.posts
                    .filter { $0.author.id == userId && $0.parentPostId != nil } // Only replies
                    .sorted(by: { $0.createdAt > $1.createdAt }) // Most recent first
                continuation.resume(returning: userReplies)
            }
        }
    }
    
    func fetchLikedPostsByUser(_ userId: String) async throws -> [Post] {
        // Get current user summary first
        let currentUser = await currentUserSummary()
        
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                // Filter posts that are liked by the current user (userId matches current user)
                let likedPosts = self.posts
                    .filter { $0.isLiked && $0.author.id == currentUser.id }
                    .sorted(by: { $0.createdAt > $1.createdAt })
                continuation.resume(returning: likedPosts)
            }
        }
    }
}