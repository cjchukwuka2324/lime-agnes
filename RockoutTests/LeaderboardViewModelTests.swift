//
//  LeaderboardViewModelTests.swift
//  RockoutTests
//
//  Created for RockOut Leaderboard Feature
//

import XCTest
@testable import Rockout

@MainActor
final class LeaderboardViewModelTests: XCTestCase {
    
    var artistLeaderboardViewModel: ArtistLeaderboardViewModel!
    var myArtistRanksViewModel: MyArtistRanksViewModel!
    
    override func setUpWithError() throws {
        artistLeaderboardViewModel = ArtistLeaderboardViewModel(artistId: "test-artist-id")
        myArtistRanksViewModel = MyArtistRanksViewModel()
    }
    
    override func tearDownWithError() throws {
        artistLeaderboardViewModel = nil
        myArtistRanksViewModel = nil
    }
    
    // MARK: - ArtistLeaderboardViewModel Tests
    
    func testInitialState() {
        XCTAssertEqual(artistLeaderboardViewModel.state, .idle)
        XCTAssertNil(artistLeaderboardViewModel.leaderboard)
        XCTAssertEqual(artistLeaderboardViewModel.selectedTimeFilter, .last30Days)
        XCTAssertEqual(artistLeaderboardViewModel.selectedRegion, .global)
    }
    
    func testTimeFilterDateCalculation() {
        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: now)!
        
        artistLeaderboardViewModel.selectedTimeFilter = .last7Days
        XCTAssertEqual(
            artistLeaderboardViewModel.startDate.timeIntervalSince1970,
            sevenDaysAgo.timeIntervalSince1970,
            accuracy: 60.0 // Allow 1 minute tolerance
        )
        XCTAssertEqual(
            artistLeaderboardViewModel.endDate.timeIntervalSince1970,
            now.timeIntervalSince1970,
            accuracy: 60.0
        )
        
        artistLeaderboardViewModel.selectedTimeFilter = .last30Days
        XCTAssertEqual(
            artistLeaderboardViewModel.startDate.timeIntervalSince1970,
            thirtyDaysAgo.timeIntervalSince1970,
            accuracy: 60.0
        )
        
        artistLeaderboardViewModel.selectedTimeFilter = .last90Days
        XCTAssertEqual(
            artistLeaderboardViewModel.startDate.timeIntervalSince1970,
            ninetyDaysAgo.timeIntervalSince1970,
            accuracy: 60.0
        )
    }
    
    func testCustomTimeFilter() {
        let startDate = Date().addingTimeInterval(-86400 * 14) // 14 days ago
        let endDate = Date()
        
        artistLeaderboardViewModel.selectedTimeFilter = .custom(start: startDate, end: endDate)
        
        XCTAssertEqual(
            artistLeaderboardViewModel.startDate.timeIntervalSince1970,
            startDate.timeIntervalSince1970,
            accuracy: 1.0
        )
        XCTAssertEqual(
            artistLeaderboardViewModel.endDate.timeIntervalSince1970,
            endDate.timeIntervalSince1970,
            accuracy: 1.0
        )
    }
    
    func testRegionFilterCode() {
        artistLeaderboardViewModel.selectedRegion = .global
        XCTAssertNil(artistLeaderboardViewModel.regionCode)
        
        artistLeaderboardViewModel.selectedRegion = .region(code: "US", name: "United States")
        XCTAssertEqual(artistLeaderboardViewModel.regionCode, "US")
    }
    
    // MARK: - MyArtistRanksViewModel Tests
    
    func testMyArtistRanksInitialState() {
        XCTAssertTrue(myArtistRanksViewModel.myArtistRanks.isEmpty)
        XCTAssertFalse(myArtistRanksViewModel.isLoading)
        XCTAssertNil(myArtistRanksViewModel.errorMessage)
        XCTAssertEqual(myArtistRanksViewModel.selectedTimeFilter, .last30Days)
        XCTAssertEqual(myArtistRanksViewModel.selectedRegion, .global)
    }
    
    func testTopRanksFiltering() {
        let ranks = [
            MyArtistRank(artistId: "1", artistName: "Artist 1", artistImageURL: nil, myRank: 1, myScore: 1000),
            MyArtistRank(artistId: "2", artistName: "Artist 2", artistImageURL: nil, myRank: 5, myScore: 800),
            MyArtistRank(artistId: "3", artistName: "Artist 3", artistImageURL: nil, myRank: 10, myScore: 600),
            MyArtistRank(artistId: "4", artistName: "Artist 4", artistImageURL: nil, myRank: 15, myScore: 400),
            MyArtistRank(artistId: "5", artistName: "Artist 5", artistImageURL: nil, myRank: nil, myScore: nil)
        ]
        
        myArtistRanksViewModel.myArtistRanks = ranks
        
        let topRanks = myArtistRanksViewModel.topRanks
        XCTAssertEqual(topRanks.count, 3) // Ranks 1, 5, 10 (all <= 10)
        
        let otherRanks = myArtistRanksViewModel.otherRanks
        XCTAssertEqual(otherRanks.count, 2) // Rank 15 and nil rank
    }
    
    func testTimeFilterAllCases() {
        let allCases = TimeFilter.allCases
        XCTAssertTrue(allCases.contains(.last7Days))
        XCTAssertTrue(allCases.contains(.last30Days))
        XCTAssertTrue(allCases.contains(.last90Days))
    }
    
    func testRegionFilterAllCases() {
        let allCases = RegionFilter.allCases
        XCTAssertTrue(allCases.contains(.global))
        XCTAssertTrue(allCases.contains { 
            if case .region(code: "US", _) = $0 { return true }
            return false
        })
    }
}

