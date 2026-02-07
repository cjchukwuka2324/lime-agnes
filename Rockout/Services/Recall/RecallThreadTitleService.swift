import Foundation
import Supabase

@MainActor
final class RecallThreadTitleService {
    static let shared = RecallThreadTitleService()
    
    private let supabase = SupabaseService.shared.client
    private let threadStore = RecallThreadStore.shared
    
    private init() {}
    
    /// Generates a thread title from the first assistant response's titleSuggestion
    /// or from the conversation context if titleSuggestion is not available
    func generateTitle(threadId: UUID, titleSuggestion: String? = nil) async throws {
        if let suggestion = titleSuggestion, !suggestion.isEmpty {
            // Use the provided suggestion
            try await threadStore.updateThread(threadId: threadId, title: suggestion)
            Logger.recall.info("Updated thread \(threadId.uuidString) title to: \(suggestion)")
            return
        }
        
        // Generate title from conversation context
        let (messages, _, _) = try await RecallService.shared.fetchMessages(threadId: threadId, cursor: nil, limit: 5)
        
        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else {
            // No user message yet, use default
            try await threadStore.updateThread(threadId: threadId, title: "New Recall")
            return
        }
        
        // Generate title from first user message
        let userText = firstUserMessage.editedTranscript ?? firstUserMessage.rawTranscript ?? firstUserMessage.text ?? ""
        
        // Simple title generation: take first few words or first sentence
        let title = generateTitleFromText(userText)
        
        try await threadStore.updateThread(threadId: threadId, title: title)
        Logger.recall.info("Generated title for thread \(threadId.uuidString): \(title)")
    }
    
    private func generateTitleFromText(_ text: String) -> String {
        // Take first sentence or first 30 characters
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        if let firstSentence = sentences.first, firstSentence.count <= 50 {
            return firstSentence.trimmingCharacters(in: .whitespaces)
        }
        
        // Otherwise, take first 30 characters
        let prefix = String(text.prefix(30))
        return prefix.trimmingCharacters(in: .whitespaces) + (text.count > 30 ? "..." : "")
    }
}






