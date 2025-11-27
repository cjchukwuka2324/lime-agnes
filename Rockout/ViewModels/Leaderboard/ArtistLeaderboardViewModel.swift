import Foundation
import SwiftUI

@MainActor
final class ArtistLeaderboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    enum LoadingState {
        case idle
        case loading
        case loaded
        case failed(String)
    }
    
    @Published var state: LoadingState = .idle
    @Published var leaderboard: ArtistLeaderboardResponse?
    @Published var selectedTimeFilter: TimeFilter = .last30Days
    @Published var selectedRegion: RegionFilter = .global
    
    // MARK: - Private Properties
    
    private let artistId: String
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
    
    // MARK: - Initialization
    
    init(artistId: String) {
        self.artistId = artistId
    }
    
    // MARK: - Load Leaderboard
    
    func load() {
        Task {
            state = .loading
            
            do {
                let response = try await leaderboardService.fetchArtistLeaderboard(
                    artistId: artistId,
                    startDate: startDate,
                    endDate: endDate,
                    region: regionCode
                )
                
                self.leaderboard = response
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
}

