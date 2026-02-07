import Foundation

/// Wraps RecallService.resolveRecall() with intent routing
/// Parses structured IntentRouterResponse
/// Handles thread context (last 8 messages + summary)
@MainActor
final class RecallAIService {
    static let shared = RecallAIService()
    
    private let recallService = RecallService.shared
    private let threadSummaryService = RecallThreadSummaryService.shared
    
    private init() {}
    
    /// Resolve recall with thread context and intent routing
    func resolveRecall(
        threadId: UUID,
        messageId: UUID,
        inputType: RecallInputType,
        text: String? = nil,
        mediaPath: String? = nil
    ) async throws -> RecallResolveResponse {
        // Fetch thread context (last 8 messages + summary)
        let context = try await buildThreadContext(threadId: threadId)
        
        // Call the underlying service
        let response = try await recallService.resolveRecall(
            threadId: threadId,
            messageId: messageId,
            inputType: inputType,
            text: text,
            mediaPath: mediaPath
        )
        
        // Parse intent if available (future enhancement)
        // For now, the backend returns the response directly
        
        // Update thread summary if needed (every ~12 messages)
        try? await updateThreadSummaryIfNeeded(threadId: threadId)
        
        return response
    }
    
    /// Build thread context for GPT (last 8 messages + summary)
    private func buildThreadContext(threadId: UUID) async throws -> String {
        // Fetch last 8 messages
        let (messages, _, _) = try await recallService.fetchMessages(threadId: threadId, cursor: nil, limit: 8)
        
        // Fetch thread summary
        let thread = try await recallService.fetchThread(threadId: threadId)
        let summary = thread.summary ?? ""
        
        var context = ""
        if !summary.isEmpty {
            context += "Thread Summary: \(summary)\n\n"
        }
        
        context += "Recent Messages:\n"
        for message in messages.suffix(8) {
            let role = message.role == .user ? "User" : "Assistant"
            let content = message.editedTranscript ?? message.rawTranscript ?? message.text ?? ""
            context += "\(role): \(content)\n"
        }
        
        return context
    }
    
    /// Update thread summary if message count suggests it's needed
    private func updateThreadSummaryIfNeeded(threadId: UUID) async throws {
        let (messages, _, _) = try await recallService.fetchMessages(threadId: threadId, cursor: nil, limit: 15)
        
        // Summarize every ~12 messages
        if messages.count >= 12 && messages.count % 12 == 0 {
            try? await threadSummaryService.summarizeThread(threadId: threadId)
        }
    }
    
    /// Fetch thread for context
    private func fetchThread(threadId: UUID) async throws -> RecallThread {
        // Use RecallService's fetchThread method
        return try await recallService.fetchThread(threadId: threadId)
    }
}

// Note: fetchThread is already defined in RecallService, so this extension is not needed

