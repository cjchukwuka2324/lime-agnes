import Foundation
import SwiftUI

@MainActor
final class MyRockListViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var myRockListRanks: [MyRockListRank] = []
    @Published var artistImages: [String: URL] = [:] // artistId -> imageURL
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTimeFilter: TimeFilter = .last30Days
    @Published var selectedRegion: RegionFilter = .global
    
    // MARK: - Private Properties
    
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
    
    // MARK: - Load Ranks
    
    func load() {
        Task {
            isLoading = true
            errorMessage = nil
            defer { isLoading = false }
            
            do {
                let ranks = try await rockListService.fetchMyRockListSummary(
                    startDate: startDate,
                    endDate: endDate,
                    region: regionCode
                )
                
                self.myRockListRanks = ranks
                
                // Fetch artist images from Spotify API
                await fetchArtistImages(for: ranks)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Fetch Artist Images
    
    private func fetchArtistImages(for ranks: [MyRockListRank]) async {
        // Get unique artist IDs
        let artistIds = Array(Set(ranks.map { $0.artistId }))
        
        // Filter out artists we already have images for
        let missingIds = artistIds.filter { artistImages[$0] == nil }
        
        guard !missingIds.isEmpty else { return }
        
        do {
            // Fetch artists from Spotify API (chunked for bulk requests)
            let artists = try await spotifyAPI.getArtists(ids: missingIds)
            
            // Store image URLs
            for artist in artists {
                if let imageURL = artist.imageURL {
                    artistImages[artist.id] = imageURL
                }
            }
        } catch {
            // Silently fail - images are optional
            print("⚠️ Failed to fetch artist images: \(error.localizedDescription)")
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
    
    // MARK: - Sorted Sections
    
    var topRanks: [MyRockListRank] {
        myRockListRanks.filter { $0.myRank != nil && ($0.myRank ?? Int.max) <= 10 }
    }
    
    var otherRanks: [MyRockListRank] {
        myRockListRanks.filter { $0.myRank == nil || ($0.myRank ?? Int.max) > 10 }
    }
}

