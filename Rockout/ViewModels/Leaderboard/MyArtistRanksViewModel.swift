import Foundation
import SwiftUI

@MainActor
final class MyArtistRanksViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var myArtistRanks: [MyArtistRank] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTimeFilter: TimeFilter = .last30Days
    @Published var selectedRegion: RegionFilter = .global
    
    // MARK: - Private Properties
    
    private let leaderboardService = LeaderboardService.shared
    
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
                let ranks = try await leaderboardService.fetchMyArtistRanks(
                    startDate: startDate,
                    endDate: endDate,
                    region: regionCode
                )
                
                self.myArtistRanks = ranks
            } catch {
                self.errorMessage = error.localizedDescription
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
    
    // MARK: - Sorted Sections
    
    var topRanks: [MyArtistRank] {
        myArtistRanks.filter { $0.myRank != nil && ($0.myRank ?? Int.max) <= 10 }
    }
    
    var otherRanks: [MyArtistRank] {
        myArtistRanks.filter { $0.myRank == nil || ($0.myRank ?? Int.max) > 10 }
    }
}

