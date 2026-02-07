import Foundation
import Supabase
import Combine

@MainActor
final class RecallService: ObservableObject {
    static let shared = RecallService()
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    // MARK: - Create Recall
    
    func createRecall(
        inputType: RecallInputType,
        rawText: String? = nil,
        mediaPath: String? = nil
    ) async throws -> UUID {
        guard let session = supabase.auth.currentSession else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let requestBody: [String: Any] = [
            "input_type": inputType.rawValue,
            "raw_text": rawText as Any,
            "media_path": mediaPath as Any,
        ]
        
        // Remove nil values
        let cleanBody = requestBody.compactMapValues { $0 }
        
        let response = try await invokeEdgeFunction(
            name: "recall_create",
            body: cleanBody,
            accessToken: session.accessToken
        )
        
        let data = try JSONDecoder().decode(RecallCreateResponse.self, from: response)
        return data.recallId
    }
    
    // MARK: - Process Recall
    
    func processRecall(recallId: UUID) async throws {
        guard let session = supabase.auth.currentSession else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let requestBody: [String: Any] = [
            "recall_id": recallId.uuidString
        ]
        
        _ = try await invokeEdgeFunction(
            name: "recall_process",
            body: requestBody,
            accessToken: session.accessToken
        )
        
        print("✅ RecallService.processRecall: Processing started for \(recallId)")
    }
    
    // MARK: - Fetch Recall Event
    
    func fetchRecall(recallId: UUID) async throws -> RecallEvent {
        let response = try await supabase
            .from("recall_events")
            .select("id, user_id, input_type, raw_text, media_path, transcript, status, confidence, error_message, created_at")
            .eq("id", value: recallId.uuidString)
            .single()
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(RecallEvent.self, from: response.data)
    }
    
    // MARK: - Fetch Candidates
    
    func fetchCandidates(recallId: UUID) async throws -> [RecallCandidate] {
        let response = try await supabase
            .from("recall_candidates")
            .select("id, recall_id, title, artist, confidence, reason, source_urls, highlight_snippet, rank, created_at")
            .eq("recall_id", value: recallId.uuidString)
            .order("rank", ascending: true)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([RecallCandidate].self, from: response.data)
    }
    
    // MARK: - Fetch Recent Recalls
    
    func fetchRecentRecalls(limit: Int = 20) async throws -> [RecallEvent] {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let response = try await supabase
            .from("recall_events")
            .select("id, user_id, input_type, raw_text, media_path, transcript, status, confidence, error_message, created_at")
            .eq("user_id", value: currentUserId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([RecallEvent].self, from: response.data)
    }
    
    // MARK: - Confirm Recall
    
    func confirmRecall(
        recallId: UUID,
        title: String,
        artist: String
    ) async throws {
        guard let session = supabase.auth.currentSession else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let requestBody: [String: Any] = [
            "recall_id": recallId.uuidString,
            "confirmed_title": title,
            "confirmed_artist": artist,
        ]
        
        _ = try await invokeEdgeFunction(
            name: "recall_confirm",
            body: requestBody,
            accessToken: session.accessToken
        )
        
        print("✅ RecallService.confirmRecall: Confirmed \(title) by \(artist)")
    }
    
    // MARK: - Ask Crowd
    
    func askCrowd(recallId: UUID) async throws -> UUID {
        guard let session = supabase.auth.currentSession else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let requestBody: [String: Any] = [
            "recall_id": recallId.uuidString
        ]
        
        let response = try await invokeEdgeFunction(
            name: "recall_ask_crowd",
            body: requestBody,
            accessToken: session.accessToken
        )
        
        let data = try JSONDecoder().decode(RecallAskCrowdResponse.self, from: response)
        return data.postId
    }
    
    // MARK: - Fetch Crowd Post
    
    func fetchCrowdPost(recallId: UUID) async throws -> UUID? {
        let response = try await supabase
            .from("recall_crowd_posts")
            .select("post_id")
            .eq("recall_id", value: recallId.uuidString)
            .single()
            .execute()
        
        let decoder = JSONDecoder()
        let crowdPost = try decoder.decode(RecallCrowdPost.self, from: response.data)
        return crowdPost.postId
    }
    
    // MARK: - Upload Media (Legacy)
    
    func uploadMedia(
        data: Data,
        recallId: UUID,
        fileName: String,
        contentType: String
    ) async throws -> String {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let path = "\(currentUserId.uuidString)/\(recallId.uuidString)/\(fileName)"
        
        try await supabase.storage
            .from("recall-media")
            .upload(path: path, file: data)
        
        return path
    }
    
    // MARK: - Thread Management (New)
    
    func createThreadIfNeeded() async throws -> UUID {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Try to get the most recent thread
        let response = try await supabase
            .from("recall_threads")
            .select("id, user_id, created_at, last_message_at, title")
            .eq("user_id", value: currentUserId.uuidString)
            .order("last_message_at", ascending: false)
            .limit(1)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let threads = try decoder.decode([RecallThread].self, from: response.data)
        if let thread = threads.first {
            // Return existing thread if it's recent (within last hour)
            let oneHourAgo = Date().addingTimeInterval(-3600)
            if thread.lastMessageAt > oneHourAgo {
                return thread.id
            }
        }
        
        // Create new thread
        struct ThreadDTO: Encodable {
            let user_id: String
        }
        
        let newThread = ThreadDTO(user_id: currentUserId.uuidString)
        
        // Select only base columns - new columns will be NULL if migration hasn't been applied
        let insertResponse = try await supabase
            .from("recall_threads")
            .insert(newThread)
            .select("id, user_id, created_at, last_message_at, title")
            .single()
            .execute()
        
        let newThreadDecoded = try decoder.decode(RecallThread.self, from: insertResponse.data)
        return newThreadDecoded.id
    }
    
    /// Creates a new thread (always creates, doesn't reuse existing)
    func createNewThread() async throws -> UUID {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        struct ThreadDTO: Encodable {
            let user_id: String
        }
        
        let newThread = ThreadDTO(user_id: currentUserId.uuidString)
        
        // Select only base columns - new columns will be NULL if migration hasn't been applied
        let insertResponse = try await supabase
            .from("recall_threads")
            .insert(newThread)
            .select("id, user_id, created_at, last_message_at, title")
            .single()
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let newThreadDecoded = try decoder.decode(RecallThread.self, from: insertResponse.data)
        
        // Verify the thread is accessible (helps with RLS visibility for FK checks)
        // Small delay to ensure transaction is committed
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        return newThreadDecoded.id
    }
    
    func fetchThread(threadId: UUID) async throws -> RecallThread {
        let startTime = Date()
        await RecallMetrics.shared.recordRequest("fetch_thread")
        
        // Check cache first
        if let cached = await RecallCache.shared.getThread(threadId) {
            print("✅ [CACHE] Using cached thread \(threadId.uuidString)")
            let duration = Date().timeIntervalSince(startTime)
            await RecallMetrics.shared.recordOperation("fetch_thread", duration: duration)
            return cached
        }
        
        // Use RequestCoalescer to prevent duplicate concurrent requests
        let coalesceKey = "recall:thread:\(threadId.uuidString)"
        
        let thread = try await RequestCoalescer.shared.execute(key: coalesceKey) {
            // Select only base columns that exist in the database
            // New columns (pinned, archived, deleted_at, summary) will be NULL if migration hasn't been applied
            let response = try await self.supabase
                .from("recall_threads")
                .select("id, user_id, created_at, last_message_at, title")
                .eq("id", value: threadId.uuidString)
                .single()
                .execute()
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(RecallThread.self, from: response.data)
        }
        
        // Cache the result
        await RecallCache.shared.setThread(thread)
        
        let duration = Date().timeIntervalSince(startTime)
        await RecallMetrics.shared.recordOperation("fetch_thread", duration: duration)
        
        return thread
    }
    
    // MARK: - Message Management
    
    func updateMessage(messageId: UUID, text: String) async throws {
        guard let session = supabase.auth.currentSession else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await supabase
            .from("recall_messages")
            .update(["text": text])
            .eq("id", value: messageId)
            .execute()
    }
    
    func insertMessage(
        threadId: UUID,
        role: RecallMessageRole,
        messageType: RecallMessageType,
        text: String? = nil,
        rawTranscript: String? = nil,
        editedTranscript: String? = nil,
        mediaPath: String? = nil,
        candidateJson: [String: AnyCodable]? = nil,
        sourcesJson: [RecallSource]? = nil,
        confidence: Double? = nil,
        songUrl: String? = nil,
        songTitle: String? = nil,
        songArtist: String? = nil
    ) async throws -> UUID {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("📝 insertMessage called: threadId=\(threadId.uuidString), role=\(role.rawValue), type=\(messageType.rawValue)")
        
        // Verify thread exists and belongs to user before inserting message
        // This ensures the thread is visible to RLS and helps with foreign key constraint
        do {
            let thread = try await fetchThread(threadId: threadId)
            // Double-check thread belongs to current user
            guard thread.userId == currentUserId else {
                throw NSError(domain: "RecallService", code: 403, userInfo: [NSLocalizedDescriptionKey: "Thread access denied"])
            }
            print("✅ Thread verified: belongs to user \(currentUserId.uuidString)")
        } catch {
            print("⚠️ Thread verification failed: \(error.localizedDescription)")
            throw NSError(domain: "RecallService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Thread not found or access denied: \(error.localizedDescription)"])
        }
        
        // Create DTO struct for message insert
        struct MessageDTO: Encodable {
            let thread_id: String
            let user_id: String
            let role: String
            let message_type: String
            let text: String?
            let raw_transcript: String?
            let edited_transcript: String?
            let media_path: String?
            let candidate_json: [String: AnyCodable]?
            let sources_json: [SourceDTO]?
            let confidence: Double?
            let song_url: String?
            let song_title: String?
            let song_artist: String?
        }
        
        struct SourceDTO: Encodable {
            let title: String
            let url: String
            let snippet: String?
        }
        
        let messageDTO = MessageDTO(
            thread_id: threadId.uuidString,
            user_id: currentUserId.uuidString,
            role: role.rawValue,
            message_type: messageType.rawValue,
            text: text,
            raw_transcript: rawTranscript,
            edited_transcript: editedTranscript,
            media_path: mediaPath,
            candidate_json: candidateJson,
            sources_json: sourcesJson?.map { SourceDTO(title: $0.title, url: $0.url, snippet: $0.snippet) },
            confidence: confidence,
            song_url: songUrl,
            song_title: songTitle,
            song_artist: songArtist
        )
        
        // Try using the RPC function first (bypasses RLS for FK check)
        // This function MUST be deployed in Supabase for message insertion to work
        do {
            // First, verify we have a valid session
            guard let session = supabase.auth.currentSession else {
                throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active session"])
            }
            print("✅ Active session found, proceeding with RPC call")
            struct InsertMessageParams: Codable {
                let p_thread_id: String
                let p_user_id: String
                let p_role: String
                let p_message_type: String
                let p_text: String?
                let p_raw_transcript: String?
                let p_edited_transcript: String?
                let p_media_path: String?
                let p_candidate_json: [String: AnyCodable]?
                let p_sources_json: [[String: String?]]?
                let p_confidence: Double?
                let p_song_url: String?
                let p_song_title: String?
                let p_song_artist: String?
            }
            
            // Convert sources to array of dictionaries
            let sourcesArray: [[String: String?]]? = sourcesJson?.map { source in
                [
                    "title": source.title,
                    "url": source.url,
                    "snippet": source.snippet
                ]
            }
            
            let params = InsertMessageParams(
                p_thread_id: threadId.uuidString,
                p_user_id: currentUserId.uuidString,
                p_role: role.rawValue,
                p_message_type: messageType.rawValue,
                p_text: text,
                p_raw_transcript: rawTranscript,
                p_edited_transcript: editedTranscript,
                p_media_path: mediaPath,
                p_candidate_json: candidateJson,
                p_sources_json: sourcesArray,
                p_confidence: confidence,
                p_song_url: songUrl,
                p_song_title: songTitle,
                p_song_artist: songArtist
            )
            
            print("🔄 Attempting to use RPC function insert_recall_message...")
            print("   Thread ID: \(threadId.uuidString)")
            print("   User ID: \(currentUserId.uuidString)")
            print("   Role: \(role.rawValue)")
            print("   Message Type: \(messageType.rawValue)")
            print("   Media Path: \(mediaPath ?? "nil")")
            
            // #region agent log
            let preCallLog: [String: Any] = [
                "location": "RecallService.insertMessage:preRPC",
                "message": "About to call RPC function",
                "threadId": threadId.uuidString,
                "userId": currentUserId.uuidString,
                "role": role.rawValue,
                "messageType": messageType.rawValue,
                "hasMediaPath": mediaPath != nil,
                "timestamp": Date().timeIntervalSince1970
            ]
            if let url = URL(string: "http://127.0.0.1:7242/ingest/ddc3f234-aa2d-49ac-904f-551be17c38c3"),
               let jsonData = try? JSONSerialization.data(withJSONObject: preCallLog) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData
                _ = try? await URLSession.shared.data(for: request)
            }
            // #endregion
            
            let functionResponse = try await supabase
                .rpc("insert_recall_message", params: params)
                .execute()
            
            // #region agent log
            let postCallLog: [String: Any] = [
                "location": "RecallService.insertMessage:postRPC",
                "message": "RPC function call succeeded",
                "responseData": String(data: functionResponse.data, encoding: .utf8) ?? "nil",
                "timestamp": Date().timeIntervalSince1970
            ]
            if let url = URL(string: "http://127.0.0.1:7242/ingest/ddc3f234-aa2d-49ac-904f-551be17c38c3"),
               let jsonData = try? JSONSerialization.data(withJSONObject: postCallLog) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData
                _ = try? await URLSession.shared.data(for: request)
            }
            // #endregion
            
            print("✅ RPC function succeeded, response data: \(String(data: functionResponse.data, encoding: .utf8) ?? "nil")")
            // RPC returns UUID - try parsing different formats
            if let responseString = String(data: functionResponse.data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) {
                if let messageId = UUID(uuidString: responseString) {
                    print("✅ Parsed message ID from RPC: \(messageId)")
                    // Invalidate cache for this thread since we have a new message
                    await RecallCache.shared.invalidateThread(threadId)
                    return messageId
                }
            }
            // Try parsing as UUID directly
            if let messageId = try? JSONDecoder().decode(UUID.self, from: functionResponse.data) {
                print("✅ Parsed message ID from RPC (direct): \(messageId)")
                // Invalidate cache for this thread since we have a new message
                await RecallCache.shared.invalidateThread(threadId)
                return messageId
            }
            // If we can't parse the response, throw an error (don't fall back to direct insert)
            let responseString = String(data: functionResponse.data, encoding: .utf8) ?? "nil"
            print("❌ RPC returned but couldn't parse UUID from response: \(responseString)")
            throw NSError(
                domain: "RecallService",
                code: 500,
                userInfo: [
                    NSLocalizedDescriptionKey: "RPC function returned invalid response format. Expected UUID, got: \(responseString)"
                ]
            )
        } catch {
            // #region agent log
            var logData: [String: Any] = [
                "location": "RecallService.insertMessage:catch",
                "message": "RPC function call failed",
                "error": error.localizedDescription,
                "errorType": String(describing: type(of: error)),
                "threadId": threadId.uuidString,
                "userId": currentUserId.uuidString,
                "role": role.rawValue,
                "messageType": messageType.rawValue,
                "timestamp": Date().timeIntervalSince1970
            ]
            if let nsError = error as? NSError {
                logData["errorCode"] = nsError.code
                logData["errorDomain"] = nsError.domain
                logData["errorUserInfo"] = nsError.userInfo
            }
            if let url = URL(string: "http://127.0.0.1:7242/ingest/ddc3f234-aa2d-49ac-904f-551be17c38c3"),
               let jsonData = try? JSONSerialization.data(withJSONObject: logData) {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData
                _ = try? await URLSession.shared.data(for: request)
            }
            // #endregion
            
            let errorDesc = error.localizedDescription
            print("❌ RPC function failed: \(errorDesc)")
            print("   Error details: \(error)")
            if let nsError = error as? NSError {
                print("   Error code: \(nsError.code)")
                print("   Error domain: \(nsError.domain)")
                print("   Error userInfo: \(nsError.userInfo)")
            }
            
            // Check if it's a "function does not exist" error
            let isFunctionMissing = errorDesc.lowercased().contains("function") && 
                                   (errorDesc.lowercased().contains("does not exist") || 
                                    errorDesc.lowercased().contains("not found"))
            
            // Check if it's an RLS error (shouldn't happen with RPC, but just in case)
            let isRLSError = errorDesc.lowercased().contains("row-level security") || 
                            errorDesc.lowercased().contains("rls") ||
                            errorDesc.lowercased().contains("policy")
            
            var userMessage = "Failed to insert message via RPC function."
            if isFunctionMissing {
                userMessage = """
                The insert_recall_message function is not deployed in your Supabase database.
                
                To fix this:
                1. Open your Supabase dashboard
                2. Go to SQL Editor
                3. Copy and run the SQL from supabase/recall.sql (lines 126-207)
                4. This will create the insert_recall_message function that bypasses RLS
                
                Error: \(errorDesc)
                """
            } else if isRLSError {
                userMessage = """
                Row-level security policy violation detected.
                
                This should not happen when using the RPC function. Possible causes:
                1. The insert_recall_message function is not deployed (see instructions above)
                2. The function exists but is not marked as SECURITY DEFINER
                3. There's an issue with the function's implementation
                
                Please ensure the function is deployed correctly.
                Error: \(errorDesc)
                """
            } else {
                userMessage = "Failed to insert message via RPC function. Error: \(errorDesc)"
            }
            
            // Don't fall back to direct insert - RLS will block it
            // The RPC function should always work if the SQL is deployed
            throw NSError(
                domain: "RecallService",
                code: 500,
                userInfo: [
                    NSLocalizedDescriptionKey: userMessage
                ]
            )
        }
        
        // This should never be reached, but just in case
        throw NSError(
            domain: "RecallService",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "RPC function returned but couldn't parse response"]
        )
    }
    
    func fetchMessages(threadId: UUID, cursor: Date? = nil, limit: Int = 50) async throws -> (messages: [RecallMessage], nextCursor: String?, hasMore: Bool) {
        let startTime = Date()
        await RecallMetrics.shared.recordRequest("fetch_messages")
        
        print("📥 [TRANSCRIPT] fetchMessages called for threadId: \(threadId.uuidString), cursor: \(cursor?.description ?? "nil"), limit: \(limit)")
        
        // Check cache first (only if no cursor - cursor means loading older messages)
        if cursor == nil {
            if let cached = await RecallCache.shared.getMessages(threadId) {
                print("✅ [CACHE] Using cached messages for thread \(threadId.uuidString)")
                let duration = Date().timeIntervalSince(startTime)
                await RecallMetrics.shared.recordOperation("fetch_messages", duration: duration)
                return (messages: cached, nextCursor: nil, hasMore: false)
            }
        }
        
        // Use RequestCoalescer to prevent duplicate concurrent requests
        let coalesceKey = "recall:messages:\(threadId.uuidString):\(cursor?.timeIntervalSince1970 ?? 0)"
        
        let result = try await RequestCoalescer.shared.execute(key: coalesceKey) {
            try await self.fetchMessagesInternal(threadId: threadId, cursor: cursor, limit: limit)
        }
        
        // Cache the result if it's the first page (no cursor)
        if cursor == nil {
            await RecallCache.shared.setMessages(threadId, messages: result.messages)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        await RecallMetrics.shared.recordOperation("fetch_messages", duration: duration)
        
        return result
    }
    
    private func fetchMessagesInternal(threadId: UUID, cursor: Date? = nil, limit: Int = 50) async throws -> (messages: [RecallMessage], nextCursor: String?, hasMore: Bool) {
        // Enforce max limit of 50 for scalability
        let effectiveLimit = min(limit, 50)
        
        // Build query with pagination
        // Note: We fetch more than needed and filter in-memory because .gt() is not available
        let fetchLimit = cursor != nil ? effectiveLimit + 50 : effectiveLimit + 1 // Fetch extra if filtering by cursor
        
        var query = supabase
            .from("recall_messages")
            .select("id, thread_id, user_id, role, message_type, text, raw_transcript, edited_transcript, media_path, candidate_json, sources_json, confidence, song_url, song_title, song_artist, created_at")
            .eq("thread_id", value: threadId.uuidString)
            .order("created_at", ascending: true)
            .limit(fetchLimit)
        
        let response = try await query.execute()
        
        print("📥 [TRANSCRIPT] Raw response data length: \(response.data.count) bytes")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var allMessages: [RecallMessage] = try decoder.decode([RecallMessage].self, from: response.data)
        
        // Apply cursor filtering in-memory if provided
        if let cursor = cursor {
            allMessages = allMessages.filter { $0.createdAt > cursor }
        }
        
        // Check if there are more pages
        let hasMore = allMessages.count > effectiveLimit
        let messages = Array(allMessages.prefix(effectiveLimit))
        
        print("📥 [TRANSCRIPT] Decoded \(messages.count) messages (hasMore: \(hasMore)):")
        for (index, msg) in messages.enumerated() {
            print("   [\(index)] id=\(msg.id), role=\(msg.role), type=\(msg.messageType), text=\(msg.text?.prefix(50) ?? "nil"), hasText=\(msg.text != nil && !msg.text!.isEmpty)")
        }
        
        // Calculate next cursor (last message's created_at)
        let nextCursor: String? = hasMore ? messages.last?.createdAt.description : nil
        
        return (messages: messages, nextCursor: nextCursor, hasMore: hasMore)
    }
    
    func updateThreadLastMessage(threadId: UUID) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await supabase
            .from("recall_threads")
            .update(["last_message_at": now])
            .eq("id", value: threadId.uuidString)
            .execute()
    }
    
    // MARK: - Media Upload (New)
    
    func uploadMedia(
        data: Data,
        threadId: UUID,
        fileName: String,
        contentType: String
    ) async throws -> String {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Verify session is active
        do {
            let session = try await supabase.auth.session
            print("✅ Active session found: user=\(session.user.id.uuidString), expires=\(session.expiresAt)")
        } catch {
            print("⚠️ Session check failed: \(error.localizedDescription)")
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired or invalid"])
        }
        
        let bucket = (contentType.hasPrefix("image/") || contentType.hasPrefix("video/")) ? "recall-images" : "recall-audio"
        let path = "\(currentUserId.uuidString)/\(threadId.uuidString)/\(fileName)"
        
        print("📤 Uploading to bucket: \(bucket)")
        print("📁 Path: \(path)")
        print("📊 File size: \(data.count) bytes")
        print("🔑 User ID: \(currentUserId.uuidString)")
        
        // Use FileOptions with upsert to handle existing files
        let options = FileOptions(upsert: true)
        do {
            try await supabase.storage
                .from(bucket)
                .upload(path: path, file: data, options: options)
            print("✅ File uploaded successfully to \(bucket)/\(path)")
        } catch {
            print("❌ Upload failed: \(error.localizedDescription)")
            print("❌ Full error: \(error)")
            if let storageError = error as? StorageError {
                print("❌ Storage error status: \(storageError.statusCode ?? "unknown")")
                print("❌ Storage error message: \(storageError.message ?? "unknown")")
            }
            throw error
        }
        
        return path
    }
    
    // MARK: - Resolve Recall
    
    func resolveRecall(
        threadId: UUID,
        messageId: UUID,
        inputType: RecallInputType,
        text: String? = nil,
        mediaPath: String? = nil,
        audioPath: String? = nil,
        videoPath: String? = nil
    ) async throws -> RecallResolveResponse {
        let requestId = UUID().uuidString.prefix(8)
        let startTime = Date()
        await RecallMetrics.shared.recordRequest("resolve_recall")
        
        print("🔍 [RECALL-SERVICE] [\(requestId)] resolveRecall() called at \(startTime)")
        print("📋 [RECALL-SERVICE] [\(requestId)] Request parameters:")
        print("   threadId: \(threadId.uuidString)")
        print("   messageId: \(messageId.uuidString)")
        print("   inputType: \(inputType.rawValue)")
        print("   text: \(text?.prefix(100) ?? "nil")")
        print("   mediaPath: \(mediaPath ?? "nil")")
        print("   audioPath: \(audioPath ?? "nil")")
        print("   videoPath: \(videoPath ?? "nil")")
        
        guard let session = supabase.auth.currentSession else {
            print("❌ [RECALL-SERVICE] [\(requestId)] Not authenticated")
            await RecallMetrics.shared.recordError("resolve_recall")
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        var requestBody: [String: Any] = [
            "thread_id": threadId.uuidString,
            "message_id": messageId.uuidString,
            "input_type": inputType.rawValue
        ]
        
        if let text = text {
            requestBody["text"] = text
        }
        if let mediaPath = mediaPath {
            requestBody["media_path"] = mediaPath
        }
        
        if let audioPath = audioPath {
            requestBody["audio_path"] = audioPath
        }
        
        if let videoPath = videoPath {
            requestBody["video_path"] = videoPath
        }
        
        // Log request body (truncate text if too long)
        var logBody = requestBody
        if let textValue = logBody["text"] as? String, textValue.count > 200 {
            logBody["text"] = String(textValue.prefix(200)) + "..."
        }
        print("📤 [RECALL-SERVICE] [\(requestId)] Request body: \(logBody)")
        
        // Use RequestCoalescer to prevent duplicate concurrent requests
        // Note: Only coalesce if same thread+message (rare, but possible with rapid taps)
        let coalesceKey = "recall:resolve:\(threadId.uuidString):\(messageId.uuidString)"
        print("🔑 [RECALL-SERVICE] [\(requestId)] Coalesce key: \(coalesceKey)")
        
        do {
            let result = try await RequestCoalescer.shared.execute(key: coalesceKey) {
                let invokeStartTime = Date()
                print("📡 [RECALL-SERVICE] [\(requestId)] Calling edge function 'recall-resolve'...")
                let response = try await self.invokeEdgeFunction(
                    name: "recall-resolve",
                    body: requestBody,
                    accessToken: session.accessToken,
                    timeout: 60.0, // Increased for transcription
                    maxRetries: 3
                )
                let invokeTime = Date().timeIntervalSince(invokeStartTime)
                print("⏱️ [RECALL-SERVICE] [\(requestId)] Edge function call took: \(String(format: "%.3f", invokeTime))s")
                print("📊 [RECALL-SERVICE] [\(requestId)] Response size: \(response.count) bytes")
                
                let decodeStartTime = Date()
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(RecallResolveResponse.self, from: response)
                let decodeTime = Date().timeIntervalSince(decodeStartTime)
                print("⏱️ [RECALL-SERVICE] [\(requestId)] JSON decode took: \(String(format: "%.3f", decodeTime))s")
                
                print("📊 [RECALL-SERVICE] [\(requestId)] Decoded response:")
                print("   status: \(decoded.status)")
                print("   responseType: \(decoded.responseType ?? "nil")")
                print("   candidates count: \(decoded.candidates?.count ?? 0)")
                print("   has answer: \(decoded.answer != nil)")
                if let candidates = decoded.candidates, !candidates.isEmpty {
                    print("   top candidate: \(candidates[0].title) by \(candidates[0].artist) (confidence: \(candidates[0].confidence))")
                }
                if let answer = decoded.answer {
                    print("   answer text length: \(answer.text.count) chars")
                    print("   answer sources: \(answer.sources.count)")
                }
                
                return decoded
            }
            
            let totalTime = Date().timeIntervalSince(startTime)
            print("✅ [RECALL-SERVICE] [\(requestId)] resolveRecall() completed in \(String(format: "%.3f", totalTime))s")
            print("📊 [RECALL-SERVICE] [\(requestId)] Final result: status=\(result.status), type=\(result.responseType ?? "none"), candidates=\(result.candidates?.count ?? 0), has_answer=\(result.answer != nil)")
            
            await RecallMetrics.shared.recordOperation("resolve_recall", duration: totalTime)
            
            // Invalidate cache for this thread since we have new messages
            await RecallCache.shared.invalidateThread(threadId)
            
            return result
        } catch {
            let totalTime = Date().timeIntervalSince(startTime)
            print("❌ [RECALL-SERVICE] [\(requestId)] resolveRecall() failed after \(String(format: "%.3f", totalTime))s")
            print("   Error: \(error.localizedDescription)")
            if let nsError = error as? NSError {
                print("   Error code: \(nsError.code)")
                print("   Error domain: \(nsError.domain)")
                print("   Error userInfo: \(nsError.userInfo)")
            }
            await RecallMetrics.shared.recordError("resolve_recall")
            await RecallMetrics.shared.recordOperation("resolve_recall", duration: totalTime)
            // Don't fallback to mock - let the error propagate so user can see what's wrong
            throw error
        }
    }
    
    // MARK: - Stash Management
    
    func fetchStash() async throws -> [RecallStashItem] {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let response = try await supabase
            .from("recall_stash")
            .select("id, user_id, thread_id, created_at, top_song_title, top_song_artist, top_confidence, top_song_url")
            .eq("user_id", value: currentUserId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([RecallStashItem].self, from: response.data)
    }
    
    func deleteFromStash(threadId: UUID) async throws {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await supabase
            .from("recall_stash")
            .delete()
            .eq("user_id", value: currentUserId.uuidString)
            .eq("thread_id", value: threadId.uuidString)
            .execute()
    }
    
    func addToStash(
        threadId: UUID,
        songTitle: String,
        songArtist: String,
        confidence: Double?
    ) async throws {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Get confidence from message if not provided
        var finalConfidence = confidence
        if finalConfidence == nil {
            let response = try await supabase
                .from("recall_messages")
                .select("confidence")
                .eq("thread_id", value: threadId.uuidString)
                .eq("message_type", value: "candidate")
                .eq("song_title", value: songTitle)
                .eq("song_artist", value: songArtist)
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
            
            let decoder = JSONDecoder()
            let data = response.data
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let firstMessage = jsonArray.first,
               let conf = firstMessage["confidence"] as? Double {
                finalConfidence = conf
            }
        }
        
        struct StashDTO: Encodable {
            let user_id: String
            let thread_id: String
            let top_song_title: String
            let top_song_artist: String
            let top_confidence: Double?
        }
        
        let stashDTO = StashDTO(
            user_id: currentUserId.uuidString,
            thread_id: threadId.uuidString,
            top_song_title: songTitle,
            top_song_artist: songArtist,
            top_confidence: finalConfidence
        )
        
        try await supabase
            .from("recall_stash")
            .upsert(stashDTO, onConflict: "user_id,thread_id")
            .execute()
    }
    
    // MARK: - Mock Response (for testing)
    
    private func createMockResponse() -> RecallResolveResponse {
        let mockSource = RecallSource(
            title: "Wikipedia",
            url: "https://example.com/song",
            snippet: "Sample song information",
            publisher: nil
        )
        
        let mockMessage = AssistantMessage(
            messageType: "candidate",
            songTitle: "Example Song",
            songArtist: "Example Artist",
            confidence: 0.85,
            reason: "This is a mock response for testing",
            lyricSnippet: "Sample lyrics",
            sources: [mockSource],
            songUrl: nil,
            allCandidates: nil
        )
        
        return RecallResolveResponse(
            status: "done",
            responseType: "search",
            transcription: nil,
            titleSuggestion: nil,
            assistantMessage: mockMessage,
            error: nil,
            candidates: nil,
            answer: nil,
            followUpQuestion: nil,
            conversationState: nil
        )
    }
}

// MARK: - Response Models

private struct RecallCreateResponse: Codable {
    let recallId: UUID
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case recallId = "recall_id"
        case status
    }
}

private struct RecallAskCrowdResponse: Codable {
    let success: Bool
    let postId: UUID
    
    enum CodingKeys: String, CodingKey {
        case success
        case postId = "post_id"
    }
}

// MARK: - Edge Function Invocation Helper

extension RecallService {
    private func invokeEdgeFunction(
        name: String,
        body: [String: Any],
        accessToken: String,
        timeout: TimeInterval = 30.0,
        maxRetries: Int = 3,
        retryDelay: TimeInterval = 1.0
    ) async throws -> Data {
        guard let supabaseURL = URL(string: Secrets.supabaseUrl) else {
            throw NSError(domain: "RecallService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
        }
        
        let functionURL = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent(name)
        
        let invokeStartTime = Date()
        var lastError: Error?
        
        // Retry loop with exponential backoff
        for attempt in 0..<maxRetries {
            do {
                var request = URLRequest(url: functionURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.timeoutInterval = timeout
                
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                // Create URLSession with timeout configuration
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = timeout
                config.timeoutIntervalForResource = timeout
                let session = URLSession(configuration: config)
                
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ [EDGE-FUNCTION] Invalid response type")
                    throw NSError(domain: "RecallService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }
                
                print("📊 [EDGE-FUNCTION] HTTP Status: \(httpResponse.statusCode)")
                
                // Success
                if (200...299).contains(httpResponse.statusCode) {
                    let totalTime = Date().timeIntervalSince(invokeStartTime)
                    print("✅ [EDGE-FUNCTION] Success in \(totalTime)s")
                    return data
                }
                
                // Rate limit - don't retry immediately
                if httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let delay = retryAfter.flatMap { Double($0) } ?? (retryDelay * pow(2.0, Double(attempt)))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                // Client errors (4xx) - don't retry
                if (400...499).contains(httpResponse.statusCode) && httpResponse.statusCode != 429 {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw NSError(
                        domain: "RecallService",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Edge function error: \(errorMessage)"]
                    )
                }
                
                // Server errors (5xx) or other errors - retry
                lastError = NSError(
                    domain: "RecallService",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Edge function error: \(String(data: data, encoding: .utf8) ?? "Unknown error")"]
                )
                
            } catch {
                // Network errors - retry
                lastError = error
            }
            
            // Exponential backoff before retry
            if attempt < maxRetries - 1 {
                let delay = retryDelay * pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // All retries exhausted
        throw lastError ?? NSError(
            domain: "RecallService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Request failed after \(maxRetries) attempts"]
        )
    }
}

