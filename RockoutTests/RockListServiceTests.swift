//
//  RockListServiceTests.swift
//  RockoutTests
//
//  Created for RockOut RockList Feature
//

import XCTest
@testable import Rockout

final class RockListServiceTests: XCTestCase {
    
    var decoder: JSONDecoder!
    
    override func setUpWithError() throws {
        decoder = JSONDecoder()
    }
    
    override func tearDownWithError() throws {
        decoder = nil
    }
    
    // MARK: - RockListEntry Decoding Tests
    
    func testDecodeRockListEntry() throws {
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
        
        let entry = try decoder.decode(RockListEntry.self, from: json)
        
        XCTAssertEqual(entry.artistId, "4Z8W4fKeB5YxbusRsdQVPb")
        XCTAssertEqual(entry.artistName, "Radiohead")
        XCTAssertEqual(entry.artistImageURL, "https://i.scdn.co/image/ab67616d0000b2739293c743fa542094336c5e12")
        XCTAssertEqual(entry.displayName, "John Doe")
        XCTAssertEqual(entry.score, 1250.5, accuracy: 0.1)
        XCTAssertEqual(entry.rank, 1)
        XCTAssertTrue(entry.isCurrentUser)
    }
    
    func testDecodeRockListEntryWithNullImage() throws {
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
        
        let entry = try decoder.decode(RockListEntry.self, from: json)
        
        XCTAssertNil(entry.artistImageURL)
        XCTAssertFalse(entry.isCurrentUser)
    }
    
    // MARK: - MyRockListRank Decoding Tests
    
    func testDecodeMyRockListRank() throws {
        let json = """
        {
            "artist_id": "4Z8W4fKeB5YxbusRsdQVPb",
            "artist_name": "Radiohead",
            "artist_image_url": "https://i.scdn.co/image/ab67616d0000b2739293c743fa542094336c5e12",
            "my_rank": 5,
            "my_score": 850.25
        }
        """.data(using: .utf8)!
        
        let rank = try decoder.decode(MyRockListRank.self, from: json)
        
        XCTAssertEqual(rank.artistId, "4Z8W4fKeB5YxbusRsdQVPb")
        XCTAssertEqual(rank.artistName, "Radiohead")
        XCTAssertEqual(rank.myRank, 5)
        XCTAssertEqual(rank.myScore, 850.25, accuracy: 0.1)
    }
    
    func testDecodeMyRockListRankWithNullRank() throws {
        let json = """
        {
            "artist_id": "4Z8W4fKeB5YxbusRsdQVPb",
            "artist_name": "Radiohead",
            "artist_image_url": null,
            "my_rank": null,
            "my_score": null
        }
        """.data(using: .utf8)!
        
        let rank = try decoder.decode(MyRockListRank.self, from: json)
        
        XCTAssertNil(rank.myRank)
        XCTAssertNil(rank.myScore)
    }
    
    // MARK: - RockListComment Decoding Tests
    
    func testDecodeRockListComment() throws {
        let json = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "display_name": "Jane Doe",
            "content": "Great artist!",
            "created_at": "2025-01-15T10:30:00.000Z",
            "artist_id": "4Z8W4fKeB5YxbusRsdQVPb",
            "studio_session_id": null,
            "comment_type": "rocklist"
        }
        """.data(using: .utf8)!
        
        let comment = try decoder.decode(RockListComment.self, from: json)
        
        XCTAssertEqual(comment.displayName, "Jane Doe")
        XCTAssertEqual(comment.content, "Great artist!")
        XCTAssertEqual(comment.artistId, "4Z8W4fKeB5YxbusRsdQVPb")
        XCTAssertNil(comment.studioSessionId)
        XCTAssertEqual(comment.commentType, "rocklist")
    }
    
    // MARK: - FeedItem Decoding Tests
    
    func testDecodeFeedItem() throws {
        let json = """
        {
            "comment_id": "123e4567-e89b-12d3-a456-426614174000",
            "user_id": "223e4567-e89b-12d3-a456-426614174000",
            "display_name": "Jane Doe",
            "content": "Check out this track!",
            "created_at": "2025-01-15T10:30:00.000Z",
            "artist_id": "4Z8W4fKeB5YxbusRsdQVPb",
            "studio_session_id": null,
            "comment_type": "rocklist"
        }
        """.data(using: .utf8)!
        
        let item = try decoder.decode(FeedItem.self, from: json)
        
        XCTAssertEqual(item.displayName, "Jane Doe")
        XCTAssertEqual(item.content, "Check out this track!")
        XCTAssertEqual(item.commentType, "rocklist")
        XCTAssertEqual(item.artistId, "4Z8W4fKeB5YxbusRsdQVPb")
    }
    
    // MARK: - RockListResponse Construction Tests
    
    func testRockListResponseConstruction() {
        let artist = ArtistSummary(
            id: "4Z8W4fKeB5YxbusRsdQVPb",
            name: "Radiohead",
            imageURL: "https://example.com/image.jpg"
        )
        
        let top20 = (1...20).map { rank in
            RockListEntry(
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
        
        let currentUser = RockListEntry(
            artistId: "4Z8W4fKeB5YxbusRsdQVPb",
            artistName: "Radiohead",
            artistImageURL: nil,
            userId: UUID(),
            displayName: "Current User",
            score: 500.0,
            rank: 25,
            isCurrentUser: true
        )
        
        let response = RockListResponse(
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

