import Foundation
import SwiftUI

// MARK: - FeedStore
// Central cache for all feed posts across tabs
// Provides instant tab switching and efficient memory management

@MainActor
final class FeedStore: ObservableObject {
    static let shared = FeedStore()
    
    // MARK: - Published Properties
    
    @Published var posts: [String: Post] = [:] // postId -> Post (deduplicated)
    
    // MARK: - Private Properties
    
    private var feedCache: [FeedType: [String]] = [:] // feedType -> [postIds] (ordered)
    private let maxPostsPerFeed = 500 // Limit to prevent memory issues
    
    private init() {}
    
    // MARK: - Cache Management
    
    /// Append posts to a specific feed cache
    func appendPosts(_ posts: [Post], for feedType: FeedType) {
        // Add posts to the main dictionary (deduplicated)
        for post in posts {
            self.posts[post.id] = post
        }
        
        // Get existing post IDs for this feed
        var existingIds = feedCache[feedType] ?? []
        
        // Append new post IDs (avoiding duplicates)
        let newIds = posts.map { $0.id }.filter { !existingIds.contains($0) }
        existingIds.append(contentsOf: newIds)
        
        // Trim if exceeds max
        if existingIds.count > maxPostsPerFeed {
            let removedIds = existingIds.prefix(existingIds.count - maxPostsPerFeed)
            existingIds = Array(existingIds.suffix(maxPostsPerFeed))
            
            // Remove old posts from main dictionary if not used by other feeds
            for removedId in removedIds {
                if !isPostUsedByOtherFeeds(removedId, exceptFeed: feedType) {
                    self.posts.removeValue(forKey: removedId)
                }
            }
        }
        
        feedCache[feedType] = existingIds
    }
    
    /// Replace all posts for a specific feed (fresh load)
    func replacePosts(_ posts: [Post], for feedType: FeedType) {
        // Add posts to main dictionary
        for post in posts {
            self.posts[post.id] = post
        }
        
        // Replace feed cache
        feedCache[feedType] = posts.map { $0.id }
        
        // Clean up unused posts
        cleanupUnusedPosts()
    }
    
    /// Get posts for a specific feed in order
    func getPostsForFeed(_ feedType: FeedType) -> [Post] {
        guard let postIds = feedCache[feedType] else { return [] }
        
        // Map IDs to posts, preserving order
        return postIds.compactMap { posts[$0] }
    }
    
    /// Clear cache for a specific feed
    func clear(feedType: FeedType) {
        let oldIds = feedCache[feedType] ?? []
        feedCache[feedType] = nil
        
        // Remove posts not used by other feeds
        for postId in oldIds {
            if !isPostUsedByOtherFeeds(postId, exceptFeed: feedType) {
                posts.removeValue(forKey: postId)
            }
        }
    }
    
    /// Clear all caches
    func clearAll() {
        posts.removeAll()
        feedCache.removeAll()
    }
    
    /// Update a single post (e.g., after like/unlike)
    func updatePost(_ post: Post) {
        posts[post.id] = post
    }
    
    /// Remove a post (e.g., after deletion)
    func removePost(_ postId: String) {
        posts.removeValue(forKey: postId)
        
        // Remove from all feed caches
        for feedType in FeedType.allCases {
            if var ids = feedCache[feedType] {
                ids.removeAll { $0 == postId }
                feedCache[feedType] = ids
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isPostUsedByOtherFeeds(_ postId: String, exceptFeed: FeedType) -> Bool {
        for (feedType, postIds) in feedCache {
            if feedType != exceptFeed && postIds.contains(postId) {
                return true
            }
        }
        return false
    }
    
    private func cleanupUnusedPosts() {
        let allUsedIds = Set(feedCache.values.flatMap { $0 })
        let allPostIds = Set(posts.keys)
        let unusedIds = allPostIds.subtracting(allUsedIds)
        
        for unusedId in unusedIds {
            posts.removeValue(forKey: unusedId)
        }
    }
    
    // MARK: - Statistics
    
    var totalPosts: Int {
        posts.count
    }
    
    var feedCacheCounts: [FeedType: Int] {
        var counts: [FeedType: Int] = [:]
        for feedType in FeedType.allCases {
            counts[feedType] = feedCache[feedType]?.count ?? 0
        }
        return counts
    }
}

// Note: FeedType conformance to CaseIterable is defined in FeedService.swift

