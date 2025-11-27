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
    
    // MARK: - Private Properties
    
    private let artistId: String
    private let rockListService = RockListService.shared
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
                self.state = .failed(error.localizedDescription)
            }
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
        guard !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isPostingComment = true
        defer { isPostingComment = false }
        
        do {
            _ = try await rockListService.postRockListComment(
                artistId: artistId,
                content: commentText.trimmingCharacters(in: .whitespacesAndNewlines),
                region: regionCode
            )
            
            commentText = ""
        } catch {
            // Handle error - could show alert
            print("Failed to post comment: \(error.localizedDescription)")
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

