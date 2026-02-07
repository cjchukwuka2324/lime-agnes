import Foundation

// MARK: - Recall Intent

enum RecallIntent: String, Codable {
    case identifySong
    case recommend
    case explainHistory
    case lyricsHelp
    case compareSongs
    case askClarify
    case generalMusicQ
}

// MARK: - Intent Router Response

struct IntentRouterResponse: Codable {
    let intent: RecallIntent
    let assistantText: String
    let confidence: Double
    let candidates: [RecallCandidateData]?
    let followUpPrompt: String?
    let followUpChips: [String]? // Quick reply options
    let sources: [RecallSource]
    let titleSuggestion: String? // For thread title generation
}






