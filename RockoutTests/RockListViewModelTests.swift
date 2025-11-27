//
//  RockListViewModelTests.swift
//  RockoutTests
//
//  Created for RockOut RockList Feature
//

import XCTest
@testable import Rockout

@MainActor
final class RockListViewModelTests: XCTestCase {
    
    var rockListViewModel: RockListViewModel!
    var myRockListViewModel: MyRockListViewModel!
    
    override func setUpWithError() throws {
        rockListViewModel = RockListViewModel(artistId: "test-artist-id")
        myRockListViewModel = MyRockListViewModel()
    }
    
    override func tearDownWithError() throws {
        rockListViewModel = nil
        myRockListViewModel = nil
    }
    
    // MARK: - RockListViewModel Tests
    
    func testInitialState() {
        XCTAssertEqual(rockListViewModel.state, .idle)
        XCTAssertNil(rockListViewModel.rockList)
        XCTAssertEqual(rockListViewModel.selectedTimeFilter, .last30Days)
        XCTAssertEqual(rockListViewModel.selectedRegion, .global)
        XCTAssertTrue(rockListViewModel.comments.isEmpty)
        XCTAssertTrue(rockListViewModel.commentText.isEmpty)
    }
    
    func testTimeFilterDateCalculation() {
        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: now)!
        
        rockListViewModel.selectedTimeFilter = .last7Days
        XCTAssertEqual(
            rockListViewModel.startDate.timeIntervalSince1970,
            sevenDaysAgo.timeIntervalSince1970,
            accuracy: 60.0 // Allow 1 minute tolerance
        )
        XCTAssertEqual(
            rockListViewModel.endDate.timeIntervalSince1970,
            now.timeIntervalSince1970,
            accuracy: 60.0
        )
        
        rockListViewModel.selectedTimeFilter = .last30Days
        XCTAssertEqual(
            rockListViewModel.startDate.timeIntervalSince1970,
            thirtyDaysAgo.timeIntervalSince1970,
            accuracy: 60.0
        )
        
        rockListViewModel.selectedTimeFilter = .last90Days
        XCTAssertEqual(
            rockListViewModel.startDate.timeIntervalSince1970,
            ninetyDaysAgo.timeIntervalSince1970,
            accuracy: 60.0
        )
    }
    
    func testCustomTimeFilter() {
        let startDate = Date().addingTimeInterval(-86400 * 14) // 14 days ago
        let endDate = Date()
        
        rockListViewModel.selectedTimeFilter = .custom(start: startDate, end: endDate)
        
        XCTAssertEqual(
            rockListViewModel.startDate.timeIntervalSince1970,
            startDate.timeIntervalSince1970,
            accuracy: 1.0
        )
        XCTAssertEqual(
            rockListViewModel.endDate.timeIntervalSince1970,
            endDate.timeIntervalSince1970,
            accuracy: 1.0
        )
    }
    
    func testRegionFilterCode() {
        rockListViewModel.selectedRegion = .global
        XCTAssertNil(rockListViewModel.regionCode)
        
        rockListViewModel.selectedRegion = .region(code: "US", name: "United States")
        XCTAssertEqual(rockListViewModel.regionCode, "US")
    }
    
    func testShareMessage() {
        let artist = ArtistSummary(id: "test", name: "Test Artist", imageURL: nil)
        let entry = RockListEntry(
            artistId: "test",
            artistName: "Test Artist",
            artistImageURL: nil,
            userId: UUID(),
            displayName: "Test User",
            score: 1000.0,
            rank: 7,
            isCurrentUser: true
        )
        let rockList = RockListResponse(artist: artist, top20: [], currentUserEntry: entry)
        
        rockListViewModel.rockList = rockList
        rockListViewModel.selectedTimeFilter = .last7Days
        rockListViewModel.selectedRegion = .global
        
        let message = rockListViewModel.shareMessage()
        XCTAssertTrue(message.contains("#7"))
        XCTAssertTrue(message.contains("Test Artist"))
        XCTAssertTrue(message.contains("RockList"))
    }
    
    // MARK: - MyRockListViewModel Tests
    
    func testMyRockListInitialState() {
        XCTAssertTrue(myRockListViewModel.myRockListRanks.isEmpty)
        XCTAssertFalse(myRockListViewModel.isLoading)
        XCTAssertNil(myRockListViewModel.errorMessage)
        XCTAssertEqual(myRockListViewModel.selectedTimeFilter, .last30Days)
        XCTAssertEqual(myRockListViewModel.selectedRegion, .global)
    }
    
    func testTopRanksFiltering() {
        let ranks = [
            MyRockListRank(artistId: "1", artistName: "Artist 1", artistImageURL: nil, myRank: 1, myScore: 1000),
            MyRockListRank(artistId: "2", artistName: "Artist 2", artistImageURL: nil, myRank: 5, myScore: 800),
            MyRockListRank(artistId: "3", artistName: "Artist 3", artistImageURL: nil, myRank: 10, myScore: 600),
            MyRockListRank(artistId: "4", artistName: "Artist 4", artistImageURL: nil, myRank: 15, myScore: 400),
            MyRockListRank(artistId: "5", artistName: "Artist 5", artistImageURL: nil, myRank: nil, myScore: nil)
        ]
        
        myRockListViewModel.myRockListRanks = ranks
        
        let topRanks = myRockListViewModel.topRanks
        XCTAssertEqual(topRanks.count, 3) // Ranks 1, 5, 10 (all <= 10)
        
        let otherRanks = myRockListViewModel.otherRanks
        XCTAssertEqual(otherRanks.count, 2) // Rank 15 and nil rank
    }
}

