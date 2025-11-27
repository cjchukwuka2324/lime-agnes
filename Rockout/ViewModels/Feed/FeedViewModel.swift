import Foundation
import SwiftUI

@MainActor
final class FeedViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    let service: FeedService
    
    // MARK: - Initialization
    
    init(service: FeedService = InMemoryFeedService.shared) {
        self.service = service
    }
    
    // MARK: - Load Feed
    
    func load(feedType: FeedType = .forYou, region: String? = nil) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            posts = try await service.fetchHomeFeed(feedType: feedType, region: region)
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading feed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Refresh
    
    func refresh(feedType: FeedType = .forYou, region: String? = nil) async {
        await load(feedType: feedType, region: region)
    }
    
    // MARK: - Create Post
    
    func createPost(text: String, imageURL: URL? = nil, videoURL: URL? = nil, audioURL: URL? = nil, leaderboardEntry: LeaderboardEntrySummary?) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageURL != nil || videoURL != nil || audioURL != nil else {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            _ = try await service.createPost(text: text, imageURL: imageURL, videoURL: videoURL, audioURL: audioURL, leaderboardEntry: leaderboardEntry)
            await load() // Refresh feed to show new post
        } catch {
            errorMessage = "Failed to create post: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Reply to Post
    
    func reply(to parentPost: Post, text: String, imageURL: URL? = nil, videoURL: URL? = nil, audioURL: URL? = nil) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageURL != nil || videoURL != nil || audioURL != nil else {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            _ = try await service.reply(to: parentPost, text: text, imageURL: imageURL, videoURL: videoURL, audioURL: audioURL)
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
            await load() // Refresh feed to show new post
        } catch {
            errorMessage = "Failed to create comment: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Toggle Like
    
    func toggleLike(postId: String) async {
        guard let currentPost = posts.first(where: { $0.id == postId }) else {
            return
        }
        
        do {
            let updatedPost: Post
            if currentPost.isLiked {
                updatedPost = try await service.unlikePost(postId)
            } else {
                updatedPost = try await service.likePost(postId)
            }
            // Update the post in the array
            if let index = posts.firstIndex(where: { $0.id == postId }) {
                posts[index] = updatedPost
            }
        } catch {
            print("Failed to toggle like: \(error)")
        }
    }
    
    // MARK: - Load User Posts
    
    func loadUserPosts(userId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            posts = try await service.fetchPostsByUser(userId)
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
}