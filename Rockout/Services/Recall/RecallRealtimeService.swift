import Foundation
import Supabase
import Combine

@MainActor
final class RecallRealtimeService: ObservableObject {
    static let shared = RecallRealtimeService()
    
    private let supabase = SupabaseService.shared.client
    private var subscriptions: [UUID: RealtimeChannel] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Subscribe to Recall Updates
    
    func subscribeToRecall(
        recallId: UUID,
        onUpdate: @escaping (RecallUpdate) -> Void,
        onError: ((Error) -> Void)? = nil
    ) {
        // Unsubscribe if already subscribed
        unsubscribeFromRecall(recallId: recallId)
        
        let channel = supabase.channel("recall_\(recallId.uuidString)")
        
        // Subscribe to recall status changes
        channel.on("postgres_changes", filter: ChannelFilter(event: "UPDATE", schema: "public", table: "recalls", filter: "id=eq.\(recallId.uuidString)")) { payload in
            Task { @MainActor in
                if let newRecord = payload.newRecord {
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let recall = try decoder.decode(RecallUpdate.self, from: JSONSerialization.data(withJSONObject: newRecord))
                        onUpdate(recall)
                    } catch {
                        onError?(error)
                    }
                }
            }
        }
        
        // Subscribe to new candidates
        channel.on("postgres_changes", filter: ChannelFilter(event: "INSERT", schema: "public", table: "recall_candidates", filter: "recall_id=eq.\(recallId.uuidString)")) { payload in
            Task { @MainActor in
                if let newRecord = payload.newRecord {
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let candidate = try decoder.decode(RecallCandidate.self, from: JSONSerialization.data(withJSONObject: newRecord))
                        let update = RecallUpdate(
                            recallId: recallId,
                            status: nil,
                            newCandidate: candidate
                        )
                        onUpdate(update)
                    } catch {
                        onError?(error)
                    }
                }
            }
        }
        
        // Subscribe to new messages
        channel.on("postgres_changes", filter: ChannelFilter(event: "INSERT", schema: "public", table: "recall_messages", filter: "thread_id=eq.\(recallId.uuidString)")) { payload in
            Task { @MainActor in
                if let newRecord = payload.newRecord {
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let message = try decoder.decode(RecallMessage.self, from: JSONSerialization.data(withJSONObject: newRecord))
                        let update = RecallUpdate(
                            recallId: recallId,
                            status: nil,
                            newMessage: message
                        )
                        onUpdate(update)
                    } catch {
                        onError?(error)
                    }
                }
            }
        }
        
        channel.subscribe { status, error in
            if let error = error {
                onError?(error)
            }
        }
        
        subscriptions[recallId] = channel
    }
    
    // MARK: - Unsubscribe
    
    func unsubscribeFromRecall(recallId: UUID) {
        if let channel = subscriptions[recallId] {
            supabase.removeChannel(channel)
            subscriptions.removeValue(forKey: recallId)
        }
    }
    
    // MARK: - Unsubscribe All
    
    func unsubscribeAll() {
        for (_, channel) in subscriptions {
            supabase.removeChannel(channel)
        }
        subscriptions.removeAll()
    }
    
    deinit {
        unsubscribeAll()
    }
}

// MARK: - Recall Update Model

struct RecallUpdate {
    let recallId: UUID
    let status: String?
    let newCandidate: RecallCandidate?
    let newMessage: RecallMessage?
    
    init(recallId: UUID, status: String?, newCandidate: RecallCandidate? = nil, newMessage: RecallMessage? = nil) {
        self.recallId = recallId
        self.status = status
        self.newCandidate = newCandidate
        self.newMessage = newMessage
    }
}




