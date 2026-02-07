import Foundation

/// RecallCache provides TTL-based caching for Recall threads and messages
/// to prevent unnecessary database queries and improve performance at scale.
actor RecallCache {
    static let shared = RecallCache()
    
    private var threadCache: [UUID: (thread: RecallThread, timestamp: Date)] = [:]
    private var messageCache: [UUID: (messages: [RecallMessage], timestamp: Date)] = [:]
    private let threadTTL: TimeInterval = 300 // 5 minutes
    private let messageTTL: TimeInterval = 60 // 1 minute
    private let maxCacheSize = 100 // Maximum number of cached items per type
    
    private init() {}
    
    // MARK: - Thread Caching
    
    func getThread(_ threadId: UUID) -> RecallThread? {
        guard let cached = threadCache[threadId],
              Date().timeIntervalSince(cached.timestamp) < threadTTL else {
            return nil
        }
        return cached.thread
    }
    
    func setThread(_ thread: RecallThread) {
        // Evict oldest if cache is full
        if threadCache.count >= maxCacheSize {
            evictOldestThread()
        }
        threadCache[thread.id] = (thread, Date())
    }
    
    func invalidateThread(_ threadId: UUID) {
        threadCache.removeValue(forKey: threadId)
        messageCache.removeValue(forKey: threadId)
    }
    
    private func evictOldestThread() {
        guard let oldest = threadCache.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
            return
        }
        threadCache.removeValue(forKey: oldest.key)
    }
    
    // MARK: - Message Caching
    
    func getMessages(_ threadId: UUID) -> [RecallMessage]? {
        guard let cached = messageCache[threadId],
              Date().timeIntervalSince(cached.timestamp) < messageTTL else {
            return nil
        }
        return cached.messages
    }
    
    func setMessages(_ threadId: UUID, messages: [RecallMessage]) {
        // Evict oldest if cache is full
        if messageCache.count >= maxCacheSize {
            evictOldestMessages()
        }
        messageCache[threadId] = (messages, Date())
    }
    
    func appendMessage(_ threadId: UUID, message: RecallMessage) {
        if var cached = messageCache[threadId],
           Date().timeIntervalSince(cached.timestamp) < messageTTL {
            cached.messages.append(message)
            messageCache[threadId] = (cached.messages, Date())
        }
    }
    
    private func evictOldestMessages() {
        guard let oldest = messageCache.min(by: { $0.value.timestamp < $1.value.timestamp }) else {
            return
        }
        messageCache.removeValue(forKey: oldest.key)
    }
    
    // MARK: - Cache Management
    
    func clearAll() {
        threadCache.removeAll()
        messageCache.removeAll()
    }
    
    func clearExpired() {
        let now = Date()
        
        // Clear expired threads
        for (key, value) in threadCache {
            if now.timeIntervalSince(value.timestamp) >= threadTTL {
                threadCache.removeValue(forKey: key)
            }
        }
        
        // Clear expired messages
        for (key, value) in messageCache {
            if now.timeIntervalSince(value.timestamp) >= messageTTL {
                messageCache.removeValue(forKey: key)
            }
        }
    }
    
    func getStats() -> (threadCount: Int, messageCount: Int) {
        return (threadCache.count, messageCache.count)
    }
}






