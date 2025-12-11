import Foundation

// MARK: - Domain-Level Naming Alias
// Backend still uses "Post" internally for database tables and API fields.
// This alias provides semantic clarity in the UI layer without breaking existing code.
typealias Bar = Post

// MARK: - User Summary

struct UserSummary: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let handle: String
    let avatarInitials: String
    let profilePictureURL: URL?
    let isFollowing: Bool  // Changed from var to let - Hashable types must be immutable
    let region: String?
    let followersCount: Int
    let followingCount: Int
    let instagramHandle: String?
    let twitterHandle: String?
    let tiktokHandle: String?
    
    init(id: String, displayName: String, handle: String, avatarInitials: String, profilePictureURL: URL? = nil, isFollowing: Bool = false, region: String? = nil, followersCount: Int = 0, followingCount: Int = 0, instagramHandle: String? = nil, twitterHandle: String? = nil, tiktokHandle: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.avatarInitials = avatarInitials
        self.profilePictureURL = profilePictureURL
        self.isFollowing = isFollowing
        self.region = region
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.instagramHandle = instagramHandle
        self.twitterHandle = twitterHandle
        self.tiktokHandle = tiktokHandle
    }
}

// MARK: - Post Summary (minimal for parent posts in replies)

struct PostSummary: Identifiable, Hashable {
    let id: String
    let text: String
    let createdAt: Date
    let author: UserSummary
    let imageURLs: [URL]
    let videoURL: URL?
    let likeCount: Int
    let replyCount: Int
    let isLiked: Bool  // Changed from var to let - Hashable types must be immutable
    let echoCount: Int
    let isEchoed: Bool
    
    init(id: String, text: String, createdAt: Date, author: UserSummary, imageURLs: [URL] = [], videoURL: URL? = nil, likeCount: Int = 0, replyCount: Int = 0, isLiked: Bool = false, echoCount: Int = 0, isEchoed: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.author = author
        self.imageURLs = imageURLs
        self.videoURL = videoURL
        self.likeCount = likeCount
        self.replyCount = replyCount
        self.isLiked = isLiked
        self.echoCount = echoCount
        self.isEchoed = isEchoed
    }
}

// MARK: - Leaderboard Entry Summary

struct LeaderboardEntrySummary: Identifiable, Hashable {
    let id: String // Composite ID: "userId_artistId"
    let userId: String
    let userDisplayName: String
    let artistId: String
    let artistName: String
    let artistImageURL: URL?
    let rank: Int
    let percentileLabel: String
    let minutesListened: Int
}

// MARK: - Post

struct Post: Identifiable, Hashable {
    let id: String
    let text: String
    let createdAt: Date
    let author: UserSummary
    let imageURLs: [URL]
    let videoURL: URL?
    let audioURL: URL?
    let likeCount: Int  // Changed from var to let - Hashable types must be immutable
    let replyCount: Int  // Changed from var to let - Hashable types must be immutable
    let isLiked: Bool  // Changed from var to let - Hashable types must be immutable
    let echoCount: Int
    let isEchoed: Bool
    let parentPostId: String?
    let parentPost: PostSummary?
    let leaderboardEntry: LeaderboardEntrySummary?
    let resharedPostId: String?
    let spotifyLink: SpotifyLink?
    let poll: Poll?
    let backgroundMusic: BackgroundMusic?
    let mentionedUserIds: [String]
    
    init(
        id: String,
        text: String,
        createdAt: Date,
        author: UserSummary,
        imageURLs: [URL] = [],
        videoURL: URL? = nil,
        audioURL: URL? = nil,
        likeCount: Int = 0,
        replyCount: Int = 0,
        isLiked: Bool = false,
        echoCount: Int = 0,
        isEchoed: Bool = false,
        parentPostId: String? = nil,
        parentPost: PostSummary? = nil,
        leaderboardEntry: LeaderboardEntrySummary? = nil,
        resharedPostId: String? = nil,
        spotifyLink: SpotifyLink? = nil,
        poll: Poll? = nil,
        backgroundMusic: BackgroundMusic? = nil,
        mentionedUserIds: [String] = []
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.author = author
        self.imageURLs = imageURLs
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.likeCount = likeCount
        self.replyCount = replyCount
        self.isLiked = isLiked
        self.echoCount = echoCount
        self.isEchoed = isEchoed
        self.parentPostId = parentPostId
        self.parentPost = parentPost
        self.leaderboardEntry = leaderboardEntry
        self.resharedPostId = resharedPostId
        self.spotifyLink = spotifyLink
        self.poll = poll
        self.backgroundMusic = backgroundMusic
        self.mentionedUserIds = mentionedUserIds
    }
    
    // Helper computed properties
    var hasMedia: Bool {
        !imageURLs.isEmpty || videoURL != nil || audioURL != nil
    }
    
    var isReply: Bool {
        parentPostId != nil
    }
}

// MARK: - Spotify Link

struct SpotifyLink: Identifiable, Hashable {
    let id: String
    let url: String
    let type: String // "track" or "playlist"
    let name: String
    let artist: String?
    let owner: String?
    let imageURL: URL?
    
    init(id: String, url: String, type: String, name: String, artist: String? = nil, owner: String? = nil, imageURL: URL? = nil) {
        self.id = id
        self.url = url
        self.type = type
        self.name = name
        self.artist = artist
        self.owner = owner
        self.imageURL = imageURL
    }
}

extension SpotifyLink: Codable {
    enum CodingKeys: String, CodingKey {
        case id, url, type, name, artist, owner, imageURL
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        owner = try container.decodeIfPresent(String.self, forKey: .owner)
        
        if let imageURLString = try container.decodeIfPresent(String.self, forKey: .imageURL) {
            imageURL = URL(string: imageURLString)
        } else {
            imageURL = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encodeIfPresent(owner, forKey: .owner)
        try container.encodeIfPresent(imageURL?.absoluteString, forKey: .imageURL)
    }
}

// MARK: - Background Music

struct BackgroundMusic: Identifiable, Hashable {
    let id: String
    let spotifyId: String
    let name: String
    let artist: String
    let previewURL: URL?
    let imageURL: URL?
    
    init(id: String? = nil, spotifyId: String, name: String, artist: String, previewURL: URL? = nil, imageURL: URL? = nil) {
        self.id = id ?? spotifyId
        self.spotifyId = spotifyId
        self.name = name
        self.artist = artist
        self.previewURL = previewURL
        self.imageURL = imageURL
    }
}

extension BackgroundMusic: Codable {
    enum CodingKeys: String, CodingKey {
        case spotifyId, name, artist, previewURL, imageURL
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spotifyId = try container.decode(String.self, forKey: .spotifyId)
        name = try container.decode(String.self, forKey: .name)
        artist = try container.decode(String.self, forKey: .artist)
        
        if let previewURLString = try container.decodeIfPresent(String.self, forKey: .previewURL) {
            previewURL = URL(string: previewURLString)
        } else {
            previewURL = nil
        }
        
        if let imageURLString = try container.decodeIfPresent(String.self, forKey: .imageURL) {
            imageURL = URL(string: imageURLString)
        } else {
            imageURL = nil
        }
        
        self.id = spotifyId
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spotifyId, forKey: .spotifyId)
        try container.encode(name, forKey: .name)
        try container.encode(artist, forKey: .artist)
        try container.encodeIfPresent(previewURL?.absoluteString, forKey: .previewURL)
        try container.encodeIfPresent(imageURL?.absoluteString, forKey: .imageURL)
    }
}

// MARK: - Poll

struct Poll: Identifiable, Hashable {
    let id: String // Post ID
    let question: String
    let options: [PollOption]
    let type: String // "single" or "multiple"
    let userVoteIndices: Set<Int> // Indices of options the current user voted for
    
    init(id: String, question: String, options: [PollOption], type: String, userVoteIndices: Set<Int> = []) {
        self.id = id
        self.question = question
        self.options = options
        self.type = type
        self.userVoteIndices = userVoteIndices
    }
    
    var totalVotes: Int {
        options.reduce(0) { $0 + $1.voteCount }
    }
}

struct PollOption: Identifiable, Hashable {
    let id: Int
    let text: String
    let voteCount: Int  // Changed from var to let - Hashable types must be immutable
    let isSelected: Bool  // Changed from var to let - Hashable types must be immutable
    
    init(id: Int, text: String, voteCount: Int = 0, isSelected: Bool = false) {
        self.id = id
        self.text = text
        self.voteCount = voteCount
        self.isSelected = isSelected
    }
    
    func percentage(of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(voteCount) / Double(total) * 100
    }
}