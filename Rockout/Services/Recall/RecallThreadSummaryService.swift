import Foundation
import Supabase

@MainActor
final class RecallThreadSummaryService {
    static let shared = RecallThreadSummaryService()
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    /// Summarizes a thread's conversation history
    /// Called when thread has ~12 messages or ~1,500 tokens
    /// Stores summary in recall_threads.summary
    /// 
    /// Note: For now, generates a simple summary from the first user message.
    /// In the future, this can call a backend edge function that uses GPT for summarization.
    func summarizeThread(threadId: UUID) async throws {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallThreadSummaryService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Fetch last ~12 messages
        let (messages, _, _) = try await RecallService.shared.fetchMessages(threadId: threadId, cursor: nil, limit: 12)
        
        guard !messages.isEmpty else { return }
        
        // Build conversation context
        var conversationText = ""
        for message in messages {
            let role = message.role == .user ? "User" : "Assistant"
            let content = message.editedTranscript ?? message.rawTranscript ?? message.text ?? ""
            conversationText += "\(role): \(content)\n"
        }
        
        // Generate a simple summary from the conversation
        let summary = generateSummary(conversation: conversationText)
        
        // Update thread with summary
        try await supabase
            .from("recall_threads")
            .update(["summary": summary])
            .eq("id", value: threadId.uuidString)
            .execute()
        
        Logger.recall.info("Generated summary for thread \(threadId.uuidString): \(summary.prefix(100))...")
    }
    
    private func generateSummary(conversation: String) -> String {
        // Simple implementation: take first user message and first assistant response
        let lines = conversation.components(separatedBy: "\n")
        var userMessages: [String] = []
        var assistantMessages: [String] = []
        
        for line in lines {
            if line.hasPrefix("User:") {
                userMessages.append(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix("Assistant:") {
                assistantMessages.append(String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces))
            }
        }
        
        // Create a simple summary from the first user message
        if let firstUser = userMessages.first, !firstUser.isEmpty {
            let summary = firstUser.prefix(100)
            return String(summary) + (firstUser.count > 100 ? "..." : "")
        }
        
        return "Music conversation"
    }
}

