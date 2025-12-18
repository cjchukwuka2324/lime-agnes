import Foundation

// MARK: - Recall Input Type

enum RecallInputType: String, Codable {
    case text
    case voice
    case image
}

// MARK: - Recall Status

enum RecallStatus: String, Codable {
    case queued
    case processing
    case done
    case needsCrowd
    case failed
}

// MARK: - Recall Orb State

enum RecallOrbState: Equatable {
    case idle
    case listening(level: CGFloat)
    case thinking
    case done(confidence: CGFloat)
    case error
}

// MARK: - Recall Message Role

enum RecallMessageRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - Recall Message Type

enum RecallMessageType: String, Codable {
    case text
    case voice
    case image
    case candidate
    case status
    case follow_up
    case answer
}

// MARK: - Recall Event

struct RecallEvent: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let inputType: RecallInputType
    let rawText: String?
    let mediaPath: String?
    let transcript: String?
    let status: RecallStatus
    let confidence: Double?
    let errorMessage: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case inputType = "input_type"
        case rawText = "raw_text"
        case mediaPath = "media_path"
        case transcript
        case status
        case confidence
        case errorMessage = "error_message"
        case createdAt = "created_at"
    }
}

// MARK: - Recall Candidate

struct RecallCandidate: Identifiable, Codable {
    let id: UUID
    let recallId: UUID
    let title: String
    let artist: String
    let confidence: Double
    let reason: String?
    let sourceUrls: [String]
    let highlightSnippet: String?
    let rank: Int
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case recallId = "recall_id"
        case title
        case artist
        case confidence
        case reason
        case sourceUrls = "source_urls"
        case highlightSnippet = "highlight_snippet"
        case rank
        case createdAt = "created_at"
    }
}

// MARK: - Recall Confirmation

struct RecallConfirmation: Identifiable, Codable {
    let id: UUID
    let recallId: UUID
    let userId: UUID
    let confirmedTitle: String
    let confirmedArtist: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case recallId = "recall_id"
        case userId = "user_id"
        case confirmedTitle = "confirmed_title"
        case confirmedArtist = "confirmed_artist"
        case createdAt = "created_at"
    }
}

// MARK: - Recall Crowd Post

struct RecallCrowdPost: Identifiable, Codable {
    let id: UUID
    let recallId: UUID
    let postId: UUID
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case recallId = "recall_id"
        case postId = "post_id"
        case createdAt = "created_at"
    }
}

// MARK: - Recall Thread

struct RecallThread: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let createdAt: Date
    let lastMessageAt: Date
    let title: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
        case title
    }
}

// MARK: - Recall Message

struct RecallMessage: Identifiable, Codable {
    let id: UUID
    let threadId: UUID
    let userId: UUID
    let createdAt: Date
    let role: RecallMessageRole
    let messageType: RecallMessageType
    let text: String?
    let mediaPath: String?
    let candidateJson: [String: AnyCodable]
    let sourcesJson: [RecallSource]
    let confidence: Double?
    let songUrl: String?
    let songTitle: String?
    let songArtist: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case userId = "user_id"
        case createdAt = "created_at"
        case role
        case messageType = "message_type"
        case text
        case mediaPath = "media_path"
        case candidateJson = "candidate_json"
        case sourcesJson = "sources_json"
        case confidence
        case songUrl = "song_url"
        case songTitle = "song_title"
        case songArtist = "song_artist"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        threadId = try container.decode(UUID.self, forKey: .threadId)
        userId = try container.decode(UUID.self, forKey: .userId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        role = try container.decode(RecallMessageRole.self, forKey: .role)
        messageType = try container.decode(RecallMessageType.self, forKey: .messageType)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        mediaPath = try container.decodeIfPresent(String.self, forKey: .mediaPath)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        songUrl = try container.decodeIfPresent(String.self, forKey: .songUrl)
        songTitle = try container.decodeIfPresent(String.self, forKey: .songTitle)
        songArtist = try container.decodeIfPresent(String.self, forKey: .songArtist)
        
        // Decode candidate_json (JSONB)
        if let candidateData = try? container.decode([String: AnyCodable].self, forKey: .candidateJson) {
            candidateJson = candidateData
        } else {
            candidateJson = [:]
        }
        
        // Decode sources_json (JSONB array)
        if let sourcesData = try? container.decode([RecallSource].self, forKey: .sourcesJson) {
            sourcesJson = sourcesData
        } else {
            sourcesJson = []
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(threadId, forKey: .threadId)
        try container.encode(userId, forKey: .userId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(role, forKey: .role)
        try container.encode(messageType, forKey: .messageType)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(mediaPath, forKey: .mediaPath)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(songUrl, forKey: .songUrl)
        try container.encodeIfPresent(songTitle, forKey: .songTitle)
        try container.encodeIfPresent(songArtist, forKey: .songArtist)
        try container.encode(candidateJson, forKey: .candidateJson)
        try container.encode(sourcesJson, forKey: .sourcesJson)
    }
    
    // Helper to extract candidate data
    var candidate: RecallCandidateData? {
        guard messageType == .candidate,
              let title = candidateJson["title"]?.value as? String,
              let artist = candidateJson["artist"]?.value as? String,
              let confidence = candidateJson["confidence"]?.value as? Double else {
            return nil
        }
        return RecallCandidateData(
            title: title,
            artist: artist,
            confidence: confidence,
            reason: candidateJson["reason"]?.value as? String,
            background: candidateJson["background"]?.value as? String,
            lyricSnippet: candidateJson["lyric_snippet"]?.value as? String
        )
    }
}

// MARK: - Recall Candidate Data (from JSON)

struct RecallCandidateData: Codable {
    let title: String
    let artist: String
    let confidence: Double
    let reason: String?
    let background: String?
    let lyricSnippet: String?
    
    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case confidence
        case reason
        case background
        case lyricSnippet = "lyric_snippet"
    }
}

// MARK: - Recall Source

struct RecallSource: Identifiable, Codable {
    let id = UUID()
    let title: String
    let url: String
    let snippet: String?
    
    enum CodingKeys: String, CodingKey {
        case title
        case url
        case snippet
    }
}

// MARK: - Recall Stash Item

struct RecallStashItem: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let threadId: UUID
    let createdAt: Date
    let topSongTitle: String?
    let topSongArtist: String?
    let topConfidence: Double?
    let topSongUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case threadId = "thread_id"
        case createdAt = "created_at"
        case topSongTitle = "top_song_title"
        case topSongArtist = "top_song_artist"
        case topConfidence = "top_confidence"
        case topSongUrl = "top_song_url"
    }
}

// MARK: - Recall Resolve Response

struct RecallResolveResponse: Codable {
    let status: String
    let responseType: String?
    let transcription: String? // Voice transcription from Whisper
    let assistantMessage: AssistantMessage?
    let error: String?
    let candidates: [CandidateInfo]?
    let answer: AnswerInfo?
    let followUpQuestion: String?
    let conversationState: String?
    
    enum CodingKeys: String, CodingKey {
        case status
        case responseType = "response_type"
        case transcription
        case assistantMessage = "assistant_message"
        case error
        case candidates
        case answer
        case followUpQuestion = "follow_up_question"
        case conversationState = "conversation_state"
    }
}

// MARK: - Answer Info

struct AnswerInfo: Codable {
    let text: String
    let sources: [String]
    let relatedSongs: [RelatedSong]?
    
    enum CodingKeys: String, CodingKey {
        case text
        case sources
        case relatedSongs = "related_songs"
    }
}

// MARK: - Related Song

struct RelatedSong: Codable {
    let title: String
    let artist: String
}

// MARK: - Assistant Message

struct AssistantMessage: Codable {
    let messageType: String
    let songTitle: String
    let songArtist: String
    let confidence: Double
    let reason: String
    let lyricSnippet: String?
    let sources: [RecallSource]
    let songUrl: String?
    let allCandidates: [CandidateInfo]?
    
    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case songTitle = "song_title"
        case songArtist = "song_artist"
        case confidence
        case reason
        case lyricSnippet = "lyric_snippet"
        case sources
        case songUrl = "song_url"
        case allCandidates = "all_candidates"
    }
}

// MARK: - Candidate Info

struct CandidateInfo: Codable {
    let title: String
    let artist: String
    let confidence: Double
    let reason: String
    let background: String?
    let lyricSnippet: String?
    let sourceUrls: [String]
    
    enum CodingKeys: String, CodingKey {
        case title
        case artist
        case confidence
        case reason
        case background
        case lyricSnippet = "lyric_snippet"
        case sourceUrls = "source_urls"
    }
}

// MARK: - AnyCodable Helper (for JSONB decoding)

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}

