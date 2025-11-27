import Foundation
import SwiftUI

@MainActor
final class FeedViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var feedItems: [FeedItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTimeFilter: TimeFilter = .last30Days
    @Published var commentText: String = ""
    @Published var isPostingComment = false
    @Published var selectedArtistId: String? = nil // For posting RockList comments
    
    // MARK: - Private Properties
    
    private let feedService = FeedService.shared
    private let rockListService = RockListService.shared
    
    // MARK: - Computed Properties
    
    var startDate: Date {
        selectedTimeFilter.startDate()
    }
    
    var endDate: Date {
        selectedTimeFilter.endDate()
    }
    
    // MARK: - Load Feed
    
    func load() {
        Task {
            await loadAsync()
        }
    }
    
    // MARK: - Load (async version)
    
    func loadAsync() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            print("🔄 Loading feed from \(startDate) to \(endDate)")
            let items = try await feedService.fetchFollowingFeed(
                startDate: startDate,
                endDate: endDate
            )
            
            print("✅ Loaded \(items.count) feed items")
            self.feedItems = items
            
            if items.isEmpty {
                print("⚠️ Feed is empty - this might mean:")
                print("   1. No comments exist in the time range")
                print("   2. You're not following any users who have commented")
                print("   3. The get_following_feed RPC might need to include your own comments")
            }
        } catch {
            print("❌ Error loading feed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Update Time Filter
    
    func updateTimeFilter(_ filter: TimeFilter) {
        selectedTimeFilter = filter
        load()
    }
    
    // MARK: - Refresh
    
    func refresh() {
        load()
    }
    
    // MARK: - Grouped Feed Items
    
    var rockListItems: [FeedItem] {
        feedItems.filter { $0.commentType == "rocklist" }
    }
    
    var studioSessionItems: [FeedItem] {
        feedItems.filter { $0.commentType == "studio_session" }
    }
    
    // MARK: - Post RockList Comment
    
    func postRockListComment(artistId: String, region: String? = nil) async {
        guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isPostingComment = true
        defer { isPostingComment = false }
        
        do {
            _ = try await rockListService.postRockListComment(
                artistId: artistId,
                content: commentText.trimmingCharacters(in: .whitespacesAndNewlines),
                region: region
            )
            
            commentText = ""
            selectedArtistId = nil
            
            // Refresh feed to show new comment
            await loadAsync()
        } catch {
            errorMessage = "Failed to post comment: \(error.localizedDescription)"
        }
    }
}

