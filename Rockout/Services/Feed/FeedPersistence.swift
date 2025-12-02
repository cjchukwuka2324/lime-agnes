import Foundation

// MARK: - Persisted Feed

struct PersistedFeed: Codable {
    let posts: [PersistedPost]
    let likesByUser: [String: [String]] // userId -> [postId]
}

// MARK: - Persisted Post

struct PersistedPost: Codable {
    let id: String
    let authorId: String
    let text: String
    let createdAt: Date
    let imageURLs: [String]? // Array of image URLs (up to 5) - optional for backward compatibility
    let imageURL: String? // Legacy single image - for backward compatibility
    let videoURL: String?
    let audioURL: String?
    let parentPostId: String?
    let leaderboardEntryId: String?
    let leaderboardArtistName: String?
    let leaderboardRank: Int?
    let leaderboardPercentileLabel: String?
    let leaderboardMinutesListened: Int?
    let resharedPostId: String?
    let likeCount: Int
    let authorProfilePictureURL: String? // Store profile picture URL for persistence (optional for backward compatibility)
}

// MARK: - Feed Persistence

enum FeedPersistence {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("feed_history.json")
    }
    
    static func save(_ persisted: PersistedFeed) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(persisted)
            try data.write(to: url)
        } catch {
            print("Failed to save feed history: \(error)")
        }
    }
    
    static func load() -> PersistedFeed? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(PersistedFeed.self, from: data)
            return decoded
        } catch {
            return nil
        }
    }
}

