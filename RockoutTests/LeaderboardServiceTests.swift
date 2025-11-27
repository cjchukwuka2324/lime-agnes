//
//  LeaderboardServiceTests.swift
//  RockoutTests
//
//  Created for RockOut Leaderboard Feature
//

import XCTest
@testable import Rockout

final class LeaderboardServiceTests: XCTestCase {
    
    var decoder: JSONDecoder!
    
    override func setUpWithError() throws {
        decoder = JSONDecoder()
    }
    
    override func tearDownWithError() throws {
        decoder = nil
    }
    
    // MARK: - ArtistLeaderboardEntry Decoding Tests
    
    func testDecodeArtistLeaderboardEntry() throws {
        let json = """
        {
            "artist_id": "4Z8W4fKeB5YxbusRsdQVPb",
            "artist_name": "Radiohead",
            "artist_image_url": "https://i.scdn.co/image/ab67616d0000b2739293c743fa542094336c5e12",
            "user_id": "123e4567-e89b-12d3-a456-426614174000",
            "display_name": "John Doe",
            "score": 1250.5,
            "rank": 1,
            "is_current_user": true
        }
        """.data(using: .utf8)!
        
        let entry = try decoder.decode(ArtistLeaderboardEntry.self, from: json)
        
        XCTAssertEqual(entry.artistId, "4Z8W4fKeB5YxbusRsdQVPb")
        XCTAssertEqual(entry.artistName, "Radiohead")
        XCTAssertEqual(entry.artistImageURL, "https://i.scdn.co/image/ab67616d0000b2739293c743fa542094336c5e12")
        XCTAssertEqual(entry.displayName, "John Doe")
        XCTAssertEqual(entry.score, 1250.5, accuracy: 0.1)
        XCTAssertEqual(entry.rank, 1)
        XCTAssertTrue(entry.isCurrentUser)
    }
    
    func testDecodeArtistLeaderboardEntryWithNullImage() throws {
        let json = """
        {
            "artist_id": "4Z8W4fKeB5YxbusRsdQVPb",
            "artist_name": "Radiohead",
            "artist_image_url": null,
            "user_id": "123e4567-e89b-12d3-a456-426614174000",
            "display_name": "John Doe",
            "score": 1250.5,
            "rank": 1,
            "is_current_user": false
        }
        """.data(using: .utf8)!
        
        let entry = try decoder.decode(ArtistLeaderboardEntry.self, from: json)
        
        XCTAssertNil(entry.artistImageURL)
        XCTAssertFalse(entry.isCurrentUser)
    }
    
    // MARK: - MyArtistRank Decoding Tests
    
    func testDecodeMyArtistRank() throws {
        let json = """
        {
            "artist_id": "4Z8W4fKeB5YxbusRsdQVPb",
            "artist_name": "Radiohead",
            "artist_image_url": "https://i.scdn.co/image/ab67616d0000b2739293c743fa542094336c5e12",
            "my_rank": 5,
            "my_score": 850.25
        }
        """.data(using: .utf8)!
        
        let rank = try decoder.decode(MyArtistRank.self, from: json)
        
        XCTAssertEqual(rank.artistId, "4Z8W4fKeB5YxbusRsdQVPb")
        XCTAssertEqual(rank.artistName, "Radiohead")
        XCTAssertEqual(rank.myRank, 5)
        XCTAssertEqual(rank.myScore, 850.25, accuracy: 0.1)
    }
    
    func testDecodeMyArtistRankWithNullRank() throws {
        let json = """
        {
            "artist_id": "4Z8W4fKeB5YxbusRsdQVPb",
            "artist_name": "Radiohead",
            "artist_image_url": null,
            "my_rank": null,
            "my_score": null
        }
        """.data(using: .utf8)!
        
        let rank = try decoder.decode(MyArtistRank.self, from: json)
        
        XCTAssertNil(rank.myRank)
        XCTAssertNil(rank.myScore)
    }
    
    // MARK: - ArtistLeaderboardResponse Construction Tests
    
    func testArtistLeaderboardResponseConstruction() {
        let artist = ArtistSummary(
            id: "4Z8W4fKeB5YxbusRsdQVPb",
            name: "Radiohead",
            imageURL: "https://example.com/image.jpg"
        )
        
        let top20 = (1...20).map { rank in
            ArtistLeaderboardEntry(
                artistId: "4Z8W4fKeB5YxbusRsdQVPb",
                artistName: "Radiohead",
                artistImageURL: nil,
                userId: UUID(),
                displayName: "User \(rank)",
                score: Double(1000 - rank * 10),
                rank: rank,
                isCurrentUser: false
            )
        }
        
        let currentUser = ArtistLeaderboardEntry(
            artistId: "4Z8W4fKeB5YxbusRsdQVPb",
            artistName: "Radiohead",
            artistImageURL: nil,
            userId: UUID(),
            displayName: "Current User",
            score: 500.0,
            rank: 25,
            isCurrentUser: true
        )
        
        let response = ArtistLeaderboardResponse(
            artist: artist,
            top20: top20,
            currentUserEntry: currentUser
        )
        
        XCTAssertEqual(response.artist.id, "4Z8W4fKeB5YxbusRsdQVPb")
        XCTAssertEqual(response.top20.count, 20)
        XCTAssertNotNil(response.currentUserEntry)
        XCTAssertEqual(response.currentUserEntry?.rank, 25)
    }
}

