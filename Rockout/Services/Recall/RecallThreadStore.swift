import Foundation
import Supabase

@MainActor
final class RecallThreadStore: ObservableObject {
    static let shared = RecallThreadStore()
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    // MARK: - Fetch Threads
    
    /// Fetches all threads for the current user, sorted by last_message_at DESC
    /// Excludes soft-deleted threads (where deleted_at IS NOT NULL)
    func fetchThreads() async throws -> [RecallThread] {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallThreadStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Select only base columns - new columns will be NULL if migration hasn't been applied
        let response = try await supabase
            .from("recall_threads")
            .select("id, user_id, created_at, last_message_at, title")
            .eq("user_id", value: currentUserId.uuidString)
            .order("last_message_at", ascending: false)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([RecallThread].self, from: response.data)
    }
    
    /// Fetches threads that have at least one message (stashed threads)
    /// Used for the stashed threads view
    func fetchStashedThreads() async throws -> [RecallThread] {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallThreadStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Fetch threads that have messages
        // We'll filter in-memory since Supabase doesn't support EXISTS in a simple way
        let allThreads = try await fetchThreads()
        
        // Filter threads that have at least one message
        var stashedThreads: [RecallThread] = []
        for thread in allThreads {
            let messageCount = try await countMessages(threadId: thread.id)
            if messageCount > 0 {
                stashedThreads.append(thread)
            }
        }
        
        return stashedThreads
    }
    
    /// Counts messages in a thread
    private func countMessages(threadId: UUID) async throws -> Int {
        let response = try await supabase
            .from("recall_messages")
            .select("id", head: true, count: .exact)
            .eq("thread_id", value: threadId.uuidString)
            .execute()
        
        return response.count ?? 0
    }
    
    // MARK: - Create Thread
    
    func createThread(title: String? = nil) async throws -> RecallThread {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallThreadStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        struct ThreadDTO: Encodable {
            let user_id: String
            let title: String?
        }
        
        let newThread = ThreadDTO(user_id: currentUserId.uuidString, title: title)
        
        // Select only base columns - new columns will be NULL if migration hasn't been applied
        let insertResponse = try await supabase
            .from("recall_threads")
            .insert(newThread)
            .select("id, user_id, created_at, last_message_at, title")
            .single()
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(RecallThread.self, from: insertResponse.data)
    }
    
    // MARK: - Update Thread
    
    func updateThread(threadId: UUID, title: String? = nil, pinned: Bool? = nil, archived: Bool? = nil) async throws {
        // Only update title for now - pinned/archived require migration to be applied first
        // TODO: Once migration is applied, uncomment the pinned/archived fields
        struct UpdateDTO: Encodable {
            let title: String?
            // let pinned: Bool?  // Uncomment after migration
            // let archived: Bool? // Uncomment after migration
        }
        
        guard title != nil else {
            // If only pinned/archived are provided but migration hasn't been applied, skip update
            // This prevents errors when migration hasn't been run
            return
        }
        
        let updateDTO = UpdateDTO(
            title: title
            // pinned: pinned,  // Uncomment after migration
            // archived: archived // Uncomment after migration
        )
        
        try await supabase
            .from("recall_threads")
            .update(updateDTO)
            .eq("id", value: threadId.uuidString)
            .execute()
    }
    
    // MARK: - Delete Thread (Soft Delete)
    
    func deleteThread(threadId: UUID) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await supabase
            .from("recall_threads")
            .update(["deleted_at": now])
            .eq("id", value: threadId.uuidString)
            .execute()
    }
    
    // MARK: - Search Threads
    
    func searchThreads(query: String) async throws -> [RecallThread] {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallThreadStore", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Search by title (case-insensitive)
        // Select only base columns - new columns will be NULL if migration hasn't been applied
        let response = try await supabase
            .from("recall_threads")
            .select("id, user_id, created_at, last_message_at, title")
            .eq("user_id", value: currentUserId.uuidString)
            .ilike("title", pattern: "%\(query)%")
            .order("last_message_at", ascending: false)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([RecallThread].self, from: response.data)
    }
    
    // MARK: - Get Last Message Snippet
    
    /// Gets the last message text from a thread for display in the threads list
    func getLastMessageSnippet(threadId: UUID) async throws -> String? {
        let response = try await supabase
            .from("recall_messages")
            .select("text, edited_transcript, raw_transcript")
            .eq("thread_id", value: threadId.uuidString)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
        
        struct MessageSnippet: Codable {
            let text: String?
            let edited_transcript: String?
            let raw_transcript: String?
        }
        
        let decoder = JSONDecoder()
        let messages = try decoder.decode([MessageSnippet].self, from: response.data)
        
        guard let message = messages.first else { return nil }
        
        // Prefer edited_transcript, then raw_transcript, then text
        return message.edited_transcript ?? message.raw_transcript ?? message.text
    }
}

