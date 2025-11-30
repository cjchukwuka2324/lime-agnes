import Foundation
import Supabase

// MARK: - Feed Type

enum FeedType: String, CaseIterable {
    case forYou = "For You"  // Region-based feed
    case following = "Following"  // Users you follow
    case trending = "Trending"  // Trending hashtags
}

// MARK: - FeedService Protocol

protocol FeedService {
    func fetchHomeFeed(feedType: FeedType, region: String?, cursor: Date?, limit: Int) async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool)
    func fetchThread(for postId: String) async throws -> (root: Post, replies: [Post])
    func fetchPostById(_ postId: String) async throws -> Post
    func fetchReplies(for postId: String) async throws -> [Post]
    
    func createPost(
        text: String,
        imageURLs: [URL],
        videoURL: URL?,
        audioURL: URL?,
        leaderboardEntry: LeaderboardEntrySummary?,
        spotifyLink: SpotifyLink?,
        poll: Poll?,
        backgroundMusic: BackgroundMusic?
    ) async throws -> Post
    
    func reply(
        to parentPost: Post,
        text: String,
        imageURLs: [URL],
        videoURL: URL?,
        audioURL: URL?,
        spotifyLink: SpotifyLink?,
        poll: Poll?,
        backgroundMusic: BackgroundMusic?
    ) async throws -> Post
    
    func deletePost(postId: String) async throws
    
    func createLeaderboardComment(
        entry: LeaderboardEntrySummary,
        text: String
    ) async throws -> Post
    
    func likePost(_ postId: String) async throws -> Bool
    func unlikePost(_ postId: String) async throws -> Bool
    func toggleLike(postId: String) async throws -> Bool
    func fetchPostsByUser(_ userId: String) async throws -> [Post]
    func fetchRepliesByUser(_ userId: String) async throws -> [Post]
    func fetchLikedPostsByUser(_ userId: String) async throws -> [Post]
}

// MARK: - In-Memory Implementation for MVP

final class InMemoryFeedService: FeedService {
    static let shared = InMemoryFeedService()
    
    private var posts: [Post] = []
    private var likesByUser: [String: Set<String>] = [:] // userId -> set of postIds
    private let queue = DispatchQueue(label: "FeedServiceQueue", qos: .userInitiated)
    private let profileService = UserProfileService.shared
    
    private init() {
        // Try to load from persistence
        if let persisted = FeedPersistence.load() {
            Task {
                await loadFromPersisted(persisted)
            }
        } else {
            seedDemoData()
        }
        
        // Initialize likesByUser for current user
        Task {
            let currentUser = await currentUserSummary()
            if likesByUser[currentUser.id] == nil {
                likesByUser[currentUser.id] = []
            }
            
            // Merge loaded posts to FeedStore (never replace, always merge to preserve all posts)
            // TODO: Implement FeedStore
            await MainActor.run {
                // let existingPostIds = Set(FeedStore.shared.posts.map { $0.id })
                // let newPosts = self.posts.filter { !existingPostIds.contains($0.id) }
                // FeedStore.shared.posts.append(contentsOf: newPosts)
                
                // Update existing posts with latest data
                // for (index, storePost) in FeedStore.shared.posts.enumerated() {
                //     if let updatedPost = self.posts.first(where: { $0.id == storePost.id }) {
                //         FeedStore.shared.posts[index] = updatedPost
                //     }
                // }
            }
        }
    }
    
    // MARK: - Persistence Helpers
    
    private func loadFromPersisted(_ persisted: PersistedFeed) async {
        let social = SupabaseSocialGraphService.shared
        let allUsers = await social.allUsers()
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.queue.async {
                // Rebuild posts from persisted data
                self.posts = persisted.posts.compactMap { persistedPost -> Post? in
                    // Find author
                    guard let author = allUsers.first(where: { $0.id == persistedPost.authorId }) else {
                        return nil
                    }
                    
                    // Rebuild leaderboard entry if present
                    let leaderboardEntry: LeaderboardEntrySummary? = {
                        guard let entryId = persistedPost.leaderboardEntryId,
                              let artistName = persistedPost.leaderboardArtistName,
                              let rank = persistedPost.leaderboardRank,
                              let percentile = persistedPost.leaderboardPercentileLabel,
                              let minutes = persistedPost.leaderboardMinutesListened else {
                            return nil
                        }
                        return LeaderboardEntrySummary(
                            id: entryId,
                            userId: persistedPost.authorId,
                            userDisplayName: author.displayName,
                            artistId: entryId, // Simplified
                            artistName: artistName,
                            artistImageURL: nil,
                            rank: rank,
                            percentileLabel: percentile,
                            minutesListened: minutes
                        )
                    }()
                    
                    // Rebuild URLs - support both new array format and legacy single image
                    let imageURLs: [URL] = {
                        if let urls = persistedPost.imageURLs, !urls.isEmpty {
                            return urls.compactMap { URL(string: $0) }
                        } else if let singleURL = persistedPost.imageURL, let url = URL(string: singleURL) {
                            return [url] // Legacy format
                        }
                        return []
                    }()
                    let videoURL = persistedPost.videoURL.flatMap { URL(string: $0) }
                    let audioURL = persistedPost.audioURL.flatMap { URL(string: $0) }
                    
                    // Rebuild parent post summary if needed
                    let parentPost: PostSummary? = nil // Would need to load parent post
                    
                    // Update author with persisted profile picture URL if available
                    var updatedAuthor = author
                    if let profilePictureURLString = persistedPost.authorProfilePictureURL,
                       let profilePictureURL = URL(string: profilePictureURLString) {
                        updatedAuthor = UserSummary(
                            id: author.id,
                            displayName: author.displayName,
                            handle: author.handle,
                            avatarInitials: author.avatarInitials,
                            profilePictureURL: profilePictureURL,
                            isFollowing: author.isFollowing
                        )
                    }
                    
                    return Post(
                        id: persistedPost.id,
                        text: persistedPost.text,
                        createdAt: persistedPost.createdAt,
                        author: updatedAuthor,
                        imageURLs: imageURLs,
                        videoURL: videoURL,
                        audioURL: audioURL,
                        likeCount: persistedPost.likeCount,
                        replyCount: 0, // Would need to calculate
                        isLiked: false, // Will be set correctly when fetching
                        parentPostId: persistedPost.parentPostId,
                        parentPost: parentPost,
                        leaderboardEntry: leaderboardEntry,
                        resharedPostId: persistedPost.resharedPostId,
                        spotifyLink: nil,
                        poll: nil,
                        backgroundMusic: nil
                    )
                }
                
                // Rebuild likesByUser
                self.likesByUser = persisted.likesByUser.reduce(into: [String: Set<String>]()) { result, pair in
                    result[pair.key] = Set(pair.value)
                }
                
                continuation.resume()
            }
        }
    }
    
    private func toPersistedFeed(from posts: [Post], likesByUser: [String: Set<String>]) -> PersistedFeed {
        let persistedPosts = posts.map { post -> PersistedPost in
            PersistedPost(
                id: post.id,
                authorId: post.author.id,
                text: post.text,
                createdAt: post.createdAt,
                imageURLs: post.imageURLs.map { $0.absoluteString },
                imageURL: post.imageURLs.first?.absoluteString, // Legacy support
                videoURL: post.videoURL?.absoluteString,
                audioURL: post.audioURL?.absoluteString,
                parentPostId: post.parentPostId,
                leaderboardEntryId: post.leaderboardEntry?.id,
                leaderboardArtistName: post.leaderboardEntry?.artistName,
                leaderboardRank: post.leaderboardEntry?.rank,
                leaderboardPercentileLabel: post.leaderboardEntry?.percentileLabel,
                leaderboardMinutesListened: post.leaderboardEntry?.minutesListened,
                resharedPostId: post.resharedPostId,
                likeCount: post.likeCount,
                authorProfilePictureURL: post.author.profilePictureURL?.absoluteString
            )
        }
        
        let persistedLikes = likesByUser.reduce(into: [String: [String]]()) { result, pair in
            result[pair.key] = Array(pair.value)
        }
        
        return PersistedFeed(posts: persistedPosts, likesByUser: persistedLikes)
    }
    
    private func syncStoreAndPersist() {
        // Capture current state from the queue context (we're already in queue.async)
        let postsCopy = self.posts
        let likesByUserCopy = self.likesByUser
        
        // Update FeedStore on main actor - merge instead of replace to preserve all posts
        // TODO: Implement FeedStore
        // Task { @MainActor in
        //     let existingPostIds = Set(FeedStore.shared.posts.map { $0.id })
        //     let newPosts = postsCopy.filter { !existingPostIds.contains($0.id) }
        //     FeedStore.shared.posts.append(contentsOf: newPosts)
        //     
        //     // Update existing posts with latest data
        //     for (index, storePost) in FeedStore.shared.posts.enumerated() {
        //         if let updatedPost = postsCopy.first(where: { $0.id == storePost.id }) {
        //             FeedStore.shared.posts[index] = updatedPost
        //         }
        //     }
        // }
        
        // Persist to disk (no need for queue.sync since we're already in queue.async)
        let persisted = toPersistedFeed(from: postsCopy, likesByUser: likesByUserCopy)
        FeedPersistence.save(persisted)
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
                profilePictureURL: pictureURL,
                isFollowing: false
            )
        }
        
        // Fallback to demo user if no profile found
        return currentDemoUser()
    }
    
    func fetchHomeFeed(feedType: FeedType, region: String?, cursor: Date?, limit: Int) async throws -> (posts: [Post], nextCursor: String?, hasMore: Bool) {
        // Refresh current user's profile data in all existing posts
        await refreshCurrentUserProfileInPosts()
        
        // Get current user and following IDs
        let currentUser = await currentUserSummary()
        let social = SupabaseSocialGraphService.shared
        let followingIds = await social.followingIds()
        
        // Get posts from FeedStore (on main actor) - this now contains ALL posts ever created
        // TODO: Implement FeedStore
        let sourcePosts = await MainActor.run {
            // FeedStore.shared.posts
            self.posts
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                // Include both root posts and replies in the timeline
                var filtered = sourcePosts
                
                // Filter by feed type
                switch feedType {
                case .forYou:
                    // For "For You", return all posts (region filtering can be added later)
                    break
                case .following:
                    // For "Following", filter by users you follow + current user's posts
                    filtered = filtered.filter { post in
                        followingIds.contains(post.author.id) || post.author.id == currentUser.id
                    }
                case .trending:
                    // For "Trending", use default (unfiltered) feed
                    // Trending is handled separately in TrendingFeedView
                    break
                }
                
                // Update isLiked based on likesByUser
                let currentUserLikes = self.likesByUser[currentUser.id] ?? []
                let sorted = filtered.map { (post: Post) -> Post in
                    let totalLikes = self.likesByUser.values.reduce(0) { count, likedPostIds in
                        count + (likedPostIds.contains(post.id) ? 1 : 0)
                    }
                    return Post(
                        id: post.id,
                        text: post.text,
                        createdAt: post.createdAt,
                        author: post.author,
                        imageURLs: post.imageURLs,
                        videoURL: post.videoURL,
                        audioURL: post.audioURL,
                        likeCount: totalLikes,
                        replyCount: post.replyCount,
                        isLiked: currentUserLikes.contains(post.id),
                        parentPostId: post.parentPostId,
                        parentPost: post.parentPost,
                        leaderboardEntry: post.leaderboardEntry,
                        resharedPostId: post.resharedPostId,
                        spotifyLink: post.spotifyLink,
                        poll: post.poll,
                        backgroundMusic: post.backgroundMusic
                    )
                }.sorted(by: { $0.createdAt > $1.createdAt })
                
                // Apply pagination
                let startIndex = cursor != nil ? (sorted.firstIndex(where: { $0.createdAt < cursor! }) ?? sorted.count) : 0
                let endIndex = min(startIndex + limit, sorted.count)
                let paginatedPosts = Array(sorted[startIndex..<endIndex])
                let hasMore = endIndex < sorted.count
                let nextCursor: String? = hasMore ? paginatedPosts.last?.createdAt.description : nil
                
                continuation.resume(returning: (posts: paginatedPosts, nextCursor: nextCursor, hasMore: hasMore))
            }
        }
    }
    
    func fetchPostById(_ postId: String) async throws -> Post {
        // In-memory implementation - find post by ID
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                guard let post = self.posts.first(where: { $0.id == postId }) else {
                    continuation.resume(throwing: NSError(domain: "FeedService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Post not found"]))
                    return
                }
                continuation.resume(returning: post)
            }
        }
    }
    
    func fetchThread(for postId: String) async throws -> (root: Post, replies: [Post]) {
        // Refresh current user's profile data in all existing posts
        await refreshCurrentUserProfileInPosts()
        
        let currentUser = await currentUserSummary()
        let currentUserLikes = await withCheckedContinuation { continuation in
            self.queue.async {
                continuation.resume(returning: self.likesByUser[currentUser.id] ?? [])
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                guard let rootIndex = self.posts.firstIndex(where: { $0.id == postId }) else {
                    continuation.resume(throwing: NSError(
                        domain: "FeedService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Post not found"]
                    ))
                    return
                }
                
                let rootPost = self.posts[rootIndex]
                let totalLikes = self.likesByUser.values.reduce(0) { count, likedPostIds in
                    count + (likedPostIds.contains(rootPost.id) ? 1 : 0)
                }
                let root = Post(
                    id: rootPost.id,
                    text: rootPost.text,
                    createdAt: rootPost.createdAt,
                    author: rootPost.author,
                    imageURLs: rootPost.imageURLs,
                    videoURL: rootPost.videoURL,
                    audioURL: rootPost.audioURL,
                    likeCount: totalLikes,
                    replyCount: rootPost.replyCount,
                    isLiked: currentUserLikes.contains(rootPost.id),
                    parentPostId: rootPost.parentPostId,
                    parentPost: rootPost.parentPost,
                    leaderboardEntry: rootPost.leaderboardEntry,
                    resharedPostId: rootPost.resharedPostId,
                    spotifyLink: rootPost.spotifyLink,
                    poll: rootPost.poll,
                    backgroundMusic: rootPost.backgroundMusic
                )
                
                let replies = self.posts
                    .filter { $0.parentPostId == postId }
                    .map { (reply: Post) -> Post in
                        let replyLikes = self.likesByUser.values.reduce(0) { count, likedPostIds in
                            count + (likedPostIds.contains(reply.id) ? 1 : 0)
                        }
                        return Post(
                            id: reply.id,
                            text: reply.text,
                            createdAt: reply.createdAt,
                            author: reply.author,
                            imageURLs: reply.imageURLs,
                            videoURL: reply.videoURL,
                            audioURL: reply.audioURL,
                            likeCount: replyLikes,
                            replyCount: reply.replyCount,
                            isLiked: currentUserLikes.contains(reply.id),
                            parentPostId: reply.parentPostId,
                            parentPost: reply.parentPost,
                            leaderboardEntry: reply.leaderboardEntry,
                            resharedPostId: reply.resharedPostId,
                            spotifyLink: reply.spotifyLink,
                            poll: reply.poll,
                            backgroundMusic: reply.backgroundMusic
                        )
                    }
                    .sorted(by: { $0.createdAt < $1.createdAt })
                
                continuation.resume(returning: (root, replies))
            }
        }
    }
    
    func createPost(
        text: String,
        imageURLs: [URL],
        videoURL: URL?,
        audioURL: URL?,
        leaderboardEntry: LeaderboardEntrySummary?,
        spotifyLink: SpotifyLink? = nil,
        poll: Poll? = nil,
        backgroundMusic: BackgroundMusic? = nil
    ) async throws -> Post {
        let author = await currentUserSummary()
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                let post = Post(
                    id: UUID().uuidString,
                    text: text,
                    createdAt: Date(),
                    author: author,
                    imageURLs: imageURLs,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    likeCount: 0,
                    replyCount: 0,
                    isLiked: false,
                    parentPostId: nil,
                    parentPost: nil,
                    leaderboardEntry: leaderboardEntry,
                    resharedPostId: nil,
                    spotifyLink: spotifyLink,
                    poll: poll,
                    backgroundMusic: backgroundMusic
                )
                self.posts.append(post)
                self.syncStoreAndPersist()
                continuation.resume(returning: post)
            }
        }
    }
    
    func reply(to parentPost: Post, text: String, imageURLs: [URL], videoURL: URL?, audioURL: URL?, spotifyLink: SpotifyLink? = nil, poll: Poll? = nil, backgroundMusic: BackgroundMusic? = nil) async throws -> Post {
        let author = await currentUserSummary()
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async(execute: DispatchWorkItem {
                // Create parent post summary for timeline display
                let parentSummary = PostSummary(
                    id: parentPost.id,
                    text: parentPost.text,
                    createdAt: parentPost.createdAt,
                    author: parentPost.author,
                    imageURLs: parentPost.imageURLs,
                    videoURL: parentPost.videoURL,
                    likeCount: parentPost.likeCount,
                    replyCount: parentPost.replyCount,
                    isLiked: parentPost.isLiked
                )
                
                let reply = Post(
                    id: UUID().uuidString,
                    text: text,
                    createdAt: Date(),
                    author: author,
                    imageURLs: imageURLs,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    likeCount: 0,
                    replyCount: 0,
                    isLiked: false,
                    parentPostId: parentPost.id,
                    parentPost: parentSummary,
                    leaderboardEntry: parentPost.leaderboardEntry,
                    resharedPostId: nil,
                    spotifyLink: spotifyLink,
                    poll: poll,
                    backgroundMusic: backgroundMusic
                )
                self.posts.append(reply)
                
                // Update parent post reply count
                if let parentIndex = self.posts.firstIndex(where: { $0.id == parentPost.id }) {
                    var updatedParent = self.posts[parentIndex]
                    updatedParent = Post(
                        id: updatedParent.id,
                        text: updatedParent.text,
                        createdAt: updatedParent.createdAt,
                        author: updatedParent.author,
                        imageURLs: updatedParent.imageURLs,
                        videoURL: updatedParent.videoURL,
                        audioURL: updatedParent.audioURL,
                        likeCount: updatedParent.likeCount,
                        replyCount: updatedParent.replyCount + 1,
                        isLiked: updatedParent.isLiked,
                        parentPostId: updatedParent.parentPostId,
                        parentPost: updatedParent.parentPost,
                        leaderboardEntry: updatedParent.leaderboardEntry,
                        resharedPostId: updatedParent.resharedPostId,
                        spotifyLink: updatedParent.spotifyLink,
                        poll: updatedParent.poll,
                        backgroundMusic: updatedParent.backgroundMusic
                    )
                    self.posts[parentIndex] = updatedParent
                    
                    // Note: Reply notifications are now created automatically by database triggers
                    // See sql/notification_triggers.sql - trg_post_reply_notification
                }
                
                self.syncStoreAndPersist()
                continuation.resume(returning: reply)
            })
        }
    }
    
    func createLeaderboardComment(
        entry: LeaderboardEntrySummary,
        text: String
    ) async throws -> Post {
        try await createPost(text: text, imageURLs: [], videoURL: nil, audioURL: nil, leaderboardEntry: entry)
    }
    
    func deletePost(postId: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                // Remove post from memory
                self.posts.removeAll { $0.id == postId }
                
                // Remove all replies to this post
                self.posts.removeAll { $0.parentPostId == postId }
                
                // Remove likes for this post
                for userId in self.likesByUser.keys {
                    self.likesByUser[userId]?.remove(postId)
                }
                
                // Update FeedStore
                // TODO: Implement FeedStore
                // Task { @MainActor in
                //     FeedStore.shared.posts.removeAll { $0.id == postId }
                //     FeedStore.shared.posts.removeAll { $0.parentPostId == postId }
                // }
                
                // Persist changes
                self.syncStoreAndPersist()
                
                continuation.resume()
            }
        }
    }
    
    func fetchReplies(for postId: String) async throws -> [Post] {
        // Refresh current user's profile data in all existing posts
        await refreshCurrentUserProfileInPosts()
        
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                let replies = self.posts
                    .filter { $0.parentPostId == postId }
                    .sorted(by: { $0.createdAt < $1.createdAt })
                continuation.resume(returning: replies)
            }
        }
    }
    
    func likePost(_ postId: String) async throws -> Bool {
        // Get current user before entering queue
        let currentUser = await currentUserSummary()
        
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async(execute: DispatchWorkItem {
                guard let index = self.posts.firstIndex(where: { $0.id == postId }) else {
                    continuation.resume(throwing: NSError(
                        domain: "FeedService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Post not found"]
                    ))
                    return
                }
                
                // Initialize likesByUser for current user if needed
                if self.likesByUser[currentUser.id] == nil {
                    self.likesByUser[currentUser.id] = []
                }
                
                var post = self.posts[index]
                if !self.likesByUser[currentUser.id]!.contains(postId) {
                    self.likesByUser[currentUser.id]!.insert(postId)
                    
                    // Update like count
                    let totalLikes = self.likesByUser.values.reduce(0) { count, likedPostIds in
                        count + (likedPostIds.contains(postId) ? 1 : 0)
                    }
                    
                    post = Post(
                        id: post.id,
                        text: post.text,
                        createdAt: post.createdAt,
                        author: post.author,
                        imageURLs: post.imageURLs,
                        videoURL: post.videoURL,
                        audioURL: post.audioURL,
                        likeCount: totalLikes,
                        replyCount: post.replyCount,
                        isLiked: true,
                        parentPostId: post.parentPostId,
                        parentPost: post.parentPost,
                        leaderboardEntry: post.leaderboardEntry,
                        resharedPostId: post.resharedPostId,
                        spotifyLink: post.spotifyLink,
                        poll: post.poll,
                        backgroundMusic: post.backgroundMusic
                    )
                    self.posts[index] = post
                    self.syncStoreAndPersist()
                    
                    // Note: Like notifications are now created automatically by database triggers
                    // See sql/notification_triggers.sql - trg_post_like_notification
                }
                continuation.resume(returning: true)
            })
        }
    }
    
    func unlikePost(_ postId: String) async throws -> Bool {
        let currentUser = await currentUserSummary()
        
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async(execute: DispatchWorkItem {
                guard let index = self.posts.firstIndex(where: { $0.id == postId }) else {
                    continuation.resume(throwing: NSError(
                        domain: "FeedService",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Post not found"]
                    ))
                    return
                }
                
                var post = self.posts[index]
                if self.likesByUser[currentUser.id]?.contains(postId) == true {
                    self.likesByUser[currentUser.id]?.remove(postId)
                    
                    // Update like count
                    let totalLikes = self.likesByUser.values.reduce(0) { count, likedPostIds in
                        count + (likedPostIds.contains(postId) ? 1 : 0)
                    }
                    
                    post = Post(
                        id: post.id,
                        text: post.text,
                        createdAt: post.createdAt,
                        author: post.author,
                        imageURLs: post.imageURLs,
                        videoURL: post.videoURL,
                        audioURL: post.audioURL,
                        likeCount: totalLikes,
                        replyCount: post.replyCount,
                        isLiked: false,
                        parentPostId: post.parentPostId,
                        parentPost: post.parentPost,
                        leaderboardEntry: post.leaderboardEntry,
                        resharedPostId: post.resharedPostId,
                        spotifyLink: post.spotifyLink,
                        poll: post.poll,
                        backgroundMusic: post.backgroundMusic
                    )
                    self.posts[index] = post
                    self.syncStoreAndPersist()
                }
                continuation.resume(returning: false)
            })
        }
    }
    
    func toggleLike(postId: String) async throws -> Bool {
        let currentUser = await currentUserSummary()
        let currentUserLikes = await withCheckedContinuation { continuation in
            self.queue.async {
                continuation.resume(returning: self.likesByUser[currentUser.id] ?? [])
            }
        }
        
        if currentUserLikes.contains(postId) {
            return try await unlikePost(postId)
        } else {
            return try await likePost(postId)
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
            profilePictureURL: nil,
            isFollowing: false
        )
    }
    
    // MARK: - Refresh Current User Profile in Posts
    
    /// Updates all posts by the current user with fresh profile data (including profile picture)
    func refreshCurrentUserProfileInPosts() async {
        // Get fresh current user summary with latest profile picture
        let freshUserSummary = await currentUserSummary()
        let currentUserId = freshUserSummary.id
        
        // Update all posts where author is current user
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.queue.async {
                for index in self.posts.indices {
                    if self.posts[index].author.id == currentUserId {
                        // Update post with fresh user summary
                        var updatedPost = self.posts[index]
                        updatedPost = Post(
                            id: updatedPost.id,
                            text: updatedPost.text,
                            createdAt: updatedPost.createdAt,
                            author: freshUserSummary, // Use fresh user summary with latest profile picture
                            imageURLs: updatedPost.imageURLs,
                            videoURL: updatedPost.videoURL,
                            audioURL: updatedPost.audioURL,
                            likeCount: updatedPost.likeCount,
                            replyCount: updatedPost.replyCount,
                            isLiked: updatedPost.isLiked,
                            parentPostId: updatedPost.parentPostId,
                            parentPost: updatedPost.parentPost,
                            leaderboardEntry: updatedPost.leaderboardEntry,
                            resharedPostId: updatedPost.resharedPostId,
                            spotifyLink: updatedPost.spotifyLink,
                            poll: updatedPost.poll,
                            backgroundMusic: updatedPost.backgroundMusic
                        )
                        self.posts[index] = updatedPost
                    }
                }
                
                // Sync to FeedStore - merge instead of replace
                // TODO: Implement FeedStore
                // let postsCopy = self.posts
                // Task { @MainActor in
                //     let existingPostIds = Set(FeedStore.shared.posts.map { $0.id })
                //     let newPosts = postsCopy.filter { !existingPostIds.contains($0.id) }
                //     FeedStore.shared.posts.append(contentsOf: newPosts)
                //     
                //     // Update existing posts with latest data
                //     for (index, storePost) in FeedStore.shared.posts.enumerated() {
                //         if let updatedPost = postsCopy.first(where: { $0.id == storePost.id }) {
                //             FeedStore.shared.posts[index] = updatedPost
                //         }
                //     }
                // }
                
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
        
        let currentUser = await currentUserSummary()
        let currentUserLikes = await withCheckedContinuation { continuation in
            self.queue.async {
                continuation.resume(returning: self.likesByUser[currentUser.id] ?? [])
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                let userPosts = self.posts
                    .filter { $0.author.id == userId && $0.parentPostId == nil } // Only root posts, no replies
                    .map { (post: Post) -> Post in
                        let totalLikes = self.likesByUser.values.reduce(0) { count, likedPostIds in
                            count + (likedPostIds.contains(post.id) ? 1 : 0)
                        }
                        return Post(
                            id: post.id,
                            text: post.text,
                            createdAt: post.createdAt,
                            author: post.author,
                            imageURLs: post.imageURLs,
                            videoURL: post.videoURL,
                            audioURL: post.audioURL,
                            likeCount: totalLikes,
                            replyCount: post.replyCount,
                            isLiked: currentUserLikes.contains(post.id),
                            parentPostId: post.parentPostId,
                            parentPost: post.parentPost,
                            leaderboardEntry: post.leaderboardEntry,
                            resharedPostId: post.resharedPostId,
                            spotifyLink: post.spotifyLink,
                            poll: post.poll,
                            backgroundMusic: post.backgroundMusic
                        )
                    }
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
            self.queue.async {
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
        let currentUserLikes = await withCheckedContinuation { continuation in
            self.queue.async {
                continuation.resume(returning: self.likesByUser[currentUser.id] ?? [])
            }
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                // Get posts liked by the specified user (not current user)
                let userLikedPostIds = self.likesByUser[userId] ?? []
                
                // Filter posts that are in the user's liked set
                let likedPosts = self.posts
                    .filter { userLikedPostIds.contains($0.id) }
                    .map { (post: Post) -> Post in
                        let totalLikes = self.likesByUser.values.reduce(0) { count, likedPostIds in
                            count + (likedPostIds.contains(post.id) ? 1 : 0)
                        }
                        return Post(
                            id: post.id,
                            text: post.text,
                            createdAt: post.createdAt,
                            author: post.author,
                            imageURLs: post.imageURLs,
                            videoURL: post.videoURL,
                            audioURL: post.audioURL,
                            likeCount: totalLikes,
                            replyCount: post.replyCount,
                            isLiked: currentUserLikes.contains(post.id),
                            parentPostId: post.parentPostId,
                            parentPost: post.parentPost,
                            leaderboardEntry: post.leaderboardEntry,
                            resharedPostId: post.resharedPostId,
                            spotifyLink: post.spotifyLink,
                            poll: post.poll,
                            backgroundMusic: post.backgroundMusic
                        )
                    }
                    .sorted(by: { $0.createdAt > $1.createdAt })
                continuation.resume(returning: likedPosts)
            }
        }
    }
}
