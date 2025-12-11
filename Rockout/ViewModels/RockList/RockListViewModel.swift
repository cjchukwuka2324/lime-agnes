import Foundation
import SwiftUI

@MainActor
final class RockListViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    enum LoadingState {
        case idle
        case loading
        case loaded
        case failed(String)
    }
    
    @Published var state: LoadingState = .idle
    @Published var rockList: RockListResponse?
    @Published var selectedTimeFilter: TimeFilter = .last30Days
    @Published var selectedRegion: RegionFilter = .global
    @Published var showShareSheet = false
    @Published var artistImageURL: URL? = nil
    @Published var commentText: String = ""
    @Published var isPostingComment = false
    @Published var createdPostId: String? = nil
    
    // MARK: - Private Properties
    
    private let artistId: String
    private let rockListService = RockListService.shared
    private let rockListDataService = RockListDataService.shared
    private let spotifyAPI = SpotifyAPI()
    
    // MARK: - Computed Properties
    
    var startDate: Date {
        selectedTimeFilter.startDate()
    }
    
    var endDate: Date {
        selectedTimeFilter.endDate()
    }
    
    var regionCode: String? {
        selectedRegion.regionCode
    }
    
    // MARK: - Initialization
    
    init(artistId: String) {
        self.artistId = artistId
    }
    
    // MARK: - Load RockList
    
    func load() {
        Task {
            state = .loading
            
            do {
                // First, ensure we have the latest data ingested (for new artists)
                await ensureLatestDataIngested()
                
                // Then fetch the RockList data
                let rockListResult = try await rockListService.fetchRockList(
                    artistId: artistId,
                    startDate: startDate,
                    endDate: endDate,
                    region: regionCode
                )
                
                self.rockList = rockListResult
                
                // Fetch artist image from Spotify API
                await fetchArtistImage()
                
                self.state = .loaded
            } catch {
                // If fetch failed, check if it's because no data exists
                // In that case, try artist-specific ingestion and retry once
                if let nsError = error as NSError?,
                   nsError.domain == "RockListService",
                   nsError.code == -1 {
                    // This is a "no data" error - try artist-specific ingestion
                    print("🔄 RockListViewModel: No data found for artist \(artistId), attempting artist-specific ingestion...")
                    
                    do {
                        // Try artist-specific ingestion (checks top tracks)
                        try await rockListDataService.ensureArtistDataIngested(artistId: artistId)
                        
                        // Wait a brief moment for backend to process
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    } catch {
                        // If artist-specific ingestion fails, fall back to regular incremental
                        print("⚠️ RockListViewModel: Artist-specific ingestion failed, trying regular incremental ingestion...")
                        await ensureLatestDataIngested()
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    }
                    
                    // Retry fetching after ingestion
                    do {
                        let rockListResult = try await rockListService.fetchRockList(
                            artistId: artistId,
                            startDate: startDate,
                            endDate: endDate,
                            region: regionCode
                        )
                        
                        self.rockList = rockListResult
                        await fetchArtistImage()
                        self.state = .loaded
                        return
                    } catch {
                        // Still failed after retry - check if it's still "no data"
                        if let retryError = error as NSError?,
                           retryError.domain == "RockListService",
                           retryError.code == -1 {
                            // Still no data - this is expected for new artists that haven't been listened to yet
                            self.state = .failed("No RockList data available for this artist yet. Start listening to see your ranking!")
                        } else {
                            // Different error - show it
                            self.state = .failed(error.localizedDescription)
                        }
                    }
                } else {
                    // Other error types - show the error
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Ensure Latest Data Ingested
    
    /// Ensures the latest listening data is ingested, including new artists
    private func ensureLatestDataIngested() async {
        // Only proceed if Spotify is authorized
        guard SpotifyAuthService.shared.isAuthorized() else {
            print("ℹ️ RockListViewModel: Spotify not authorized, skipping ingestion")
            return
        }
        
        // Double-check token validity by attempting to refresh if needed
        // This helps avoid making API calls with expired tokens
        do {
            _ = try await SpotifyAuthService.shared.refreshAccessTokenIfNeeded()
        } catch {
            // Token refresh failed - skip ingestion to avoid auth errors
            print("ℹ️ RockListViewModel: Token refresh failed, skipping ingestion")
            return
        }
        
        do {
            // Check if we need to perform initial ingestion
            let lastIngested = try? await rockListDataService.getLastIngestedTimestamp()
            
            if lastIngested == nil {
                // Perform initial bootstrap ingestion
                print("🚀 RockListViewModel: No previous ingestion found. Starting initial ingestion...")
                try await rockListDataService.performInitialBootstrapIngestion()
                print("✅ RockListViewModel: Initial ingestion completed")
            } else {
                // Perform incremental ingestion for recent plays (includes new artists)
                print("🔄 RockListViewModel: Performing incremental ingestion for new artists...")
                try await rockListDataService.performIncrementalIngestion(lastIngestedAt: lastIngested)
                print("✅ RockListViewModel: Incremental ingestion completed")
            }
        } catch {
            // Handle different types of errors gracefully
            if let nsError = error as NSError? {
                // Check if it's an authentication/authorization error
                if nsError.domain == "SpotifyAPI" && nsError.code == 403 {
                    // 403 Forbidden - user needs to reauthorize with new scope
                    print("ℹ️ RockListViewModel: Spotify access denied. User may need to reconnect Spotify in Profile settings to grant 'recently played' permission.")
                } else if nsError.domain == "SpotifyAPI" && nsError.code == 401 {
                    // 401 Unauthorized - token expired or invalid
                    print("ℹ️ RockListViewModel: Spotify authentication expired. User may need to reconnect Spotify.")
                } else {
                    // Other errors - log but don't fail
                    print("⚠️ RockListViewModel: Failed to ingest data: \(error.localizedDescription)")
                }
            } else {
                // Unknown error type - log briefly
                print("⚠️ RockListViewModel: Ingestion failed: \(error.localizedDescription)")
            }
            // Don't throw - ingestion is best effort and shouldn't block RockList loading
        }
    }
    
    // MARK: - Update Filters
    
    func updateFilters(timeFilter: TimeFilter, region: RegionFilter) {
        selectedTimeFilter = timeFilter
        selectedRegion = region
        load()
    }
    
    // MARK: - Refresh
    
    func refresh() {
        load()
    }
    
    // MARK: - Post Comment
    
    func postComment() async {
        guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let rockList = rockList,
              let currentUserEntry = rockList.currentUserEntry else {
            return
        }
        
        isPostingComment = true
        defer { isPostingComment = false }
        
        do {
            // Create leaderboard entry for current user
            let leaderboardEntry = LeaderboardEntrySummary(
                id: "\(artistId)-\(currentUserEntry.userId.uuidString)",
                userId: currentUserEntry.userId.uuidString,
                userDisplayName: currentUserEntry.displayName,
                artistId: artistId,
                artistName: rockList.artist.name,
                artistImageURL: rockList.artist.imageURL.flatMap { URL(string: $0) },
                rank: currentUserEntry.rank,
                percentileLabel: calculatePercentileLabel(rank: currentUserEntry.rank, totalUsers: 100),
                minutesListened: Int(currentUserEntry.score / 60) // Approximate minutes from score
            )
            
            // Create post in GreenRoom with leaderboard entry
            let feedService = SupabaseFeedService.shared
            let postText = "\(commentText.trimmingCharacters(in: .whitespacesAndNewlines))\n\n#\(currentUserEntry.rank) for \(rockList.artist.name)"
            
            let createdPost = try await feedService.createPost(
                text: postText,
                imageURLs: [],
                videoURL: nil,
                audioURL: nil,
                leaderboardEntry: leaderboardEntry,
                spotifyLink: nil,
                poll: nil,
                backgroundMusic: nil,
                mentionedUserIds: []
            )
            
            // Store created post ID for navigation
            createdPostId = createdPost.id
            
            // Post notification to refresh feed
            NotificationCenter.default.post(name: .feedDidUpdate, object: nil)
            
            commentText = ""
        } catch {
            // Handle error - could show alert
            print("Failed to post comment: \(error.localizedDescription)")
        }
    }
    
    private func calculatePercentileLabel(rank: Int, totalUsers: Int = 100) -> String {
        guard totalUsers > 0, rank > 0 else { return "Top 100%" }
        guard rank <= totalUsers else { return "Top 1%" }
        let percentile = Double(totalUsers - rank) / Double(totalUsers) * 100.0
        guard percentile.isFinite && !percentile.isNaN else { return "Top 50%" }
        let percentileInt = max(1, min(100, Int(percentile.rounded())))
        
        if percentileInt >= 99 {
            return "Top 1%"
        } else if percentileInt >= 95 {
            return "Top 5%"
        } else if percentileInt >= 90 {
            return "Top 10%"
        } else if percentileInt >= 75 {
            return "Top 25%"
        } else if percentileInt >= 50 {
            return "Top 50%"
        } else {
            return "Top \(percentileInt)%"
        }
    }
    
    // MARK: - Fetch Artist Image
    
    private func fetchArtistImage() async {
        // If we already have an image URL from backend, use it
        if let backendImageURL = rockList?.artist.imageURL, let url = URL(string: backendImageURL) {
            artistImageURL = url
            return
        }
        
        // Otherwise, fetch from Spotify API
        do {
            let artist = try await spotifyAPI.getArtist(id: artistId)
            artistImageURL = artist.imageURL
        } catch {
            // Silently fail - image is optional
            print("⚠️ Failed to fetch artist image: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Share Message
    
    func shareMessage() -> String {
        guard let entry = rockList?.currentUserEntry else {
            return "Check out my RockList rankings on RockOut!"
        }
        
        let artistName = rockList?.artist.name ?? "this artist"
        let timeFilter = selectedTimeFilter.displayName.lowercased()
        let region = selectedRegion.displayName
        
        return "I'm #\(entry.rank) for \(artistName) this \(timeFilter) on RockList (RockOut). Where do you rank? \(region)"
    }
}

