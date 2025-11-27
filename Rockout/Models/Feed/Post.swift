import Foundation

// MARK: - User Summary

struct UserSummary: Identifiable, Hashable {
    let id: String
    let displayName: String
    let handle: String
    let avatarInitials: String
    let profilePictureURL: URL?
    
    init(id: String, displayName: String, handle: String, avatarInitials: String, profilePictureURL: URL? = nil) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.avatarInitials = avatarInitials
        self.profilePictureURL = profilePictureURL
    }
}

// MARK: - Leaderboard Entry Summary

struct LeaderboardEntrySummary: Identifiable, Hashable {
    let id: String
    let userId: String  // User ID for the rank entry
    let userDisplayName: String  // User's display name for the rank entry
    let artistId: String  // Artist ID for navigation
    let artistName: String
    let artistImageURL: URL?
    let rank: Int
    let percentileLabel: String   // e.g. "Top 1%"
    let minutesListened: Int
    
    init(
        id: String,
        userId: String,
        userDisplayName: String,
        artistId: String,
        artistName: String,
        artistImageURL: URL?,
        rank: Int,
        percentileLabel: String,
        minutesListened: Int
    ) {
        self.id = id
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.artistId = artistId
        self.artistName = artistName
        self.artistImageURL = artistImageURL
        self.rank = rank
        self.percentileLabel = percentileLabel
        self.minutesListened = minutesListened
    }
}

// MARK: - Post

struct Post: Identifiable, Hashable {
    let id: String
    let author: UserSummary
    let text: String
    let createdAt: Date
    
    /// Image attachment URL for photo posts
    let imageURL: URL?
    
    /// Video attachment URL for video posts
    let videoURL: URL?
    
    /// Audio attachment URL for voice recordings
    let audioURL: URL?
    
    /// If this is a reply, parentPostId is the ID of the parent.
    let parentPostId: String?
    
    /// Summary of the parent post being replied to (for display in timeline)
    let parentPostSummary: PostSummary?
    
    /// If this post is directly tied to a RockList leaderboard entry.
    let leaderboardEntry: LeaderboardEntrySummary?
    
    /// If this post is a reshare / quote of another post, this is the ID of the original post.
    let resharedPostId: String?
    
    /// Number of likes this post has received
    var likeCount: Int
    
    /// Whether the current user has liked this post
    var isLiked: Bool
    
    /// Number of replies to this post
    var replyCount: Int
    
    init(
        id: String,
        author: UserSummary,
        text: String,
        createdAt: Date,
        imageURL: URL? = nil,
        videoURL: URL? = nil,
        audioURL: URL? = nil,
        parentPostId: String? = nil,
        parentPostSummary: PostSummary? = nil,
        leaderboardEntry: LeaderboardEntrySummary? = nil,
        resharedPostId: String? = nil,
        likeCount: Int = 0,
        isLiked: Bool = false,
        replyCount: Int = 0
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.parentPostId = parentPostId
        self.parentPostSummary = parentPostSummary
        self.leaderboardEntry = leaderboardEntry
        self.resharedPostId = resharedPostId
        self.likeCount = likeCount
        self.isLiked = isLiked
        self.replyCount = replyCount
    }
}

// MARK: - Post Summary (for parent post references)

struct PostSummary: Identifiable, Hashable {
    let id: String
    let author: UserSummary
    let text: String
    let imageURL: URL?
    let videoURL: URL?
    let audioURL: URL?
    
    init(
        id: String,
        author: UserSummary,
        text: String,
        imageURL: URL? = nil,
        videoURL: URL? = nil,
        audioURL: URL? = nil
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.audioURL = audioURL
    }
}
