import Foundation
import Supabase
import Combine

@MainActor
final class RecallRealtimeService: ObservableObject {
    static let shared = RecallRealtimeService()
    
    private let supabase = SupabaseService.shared.client
    private var subscriptions: [UUID: RealtimeChannelV2] = [:]
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
        
        // TODO: Re-implement realtime subscriptions based on your Supabase Swift client version
        // The API may vary. Check your Supabase package version and documentation.
        // Common approaches:
        // 1. channel.onPostgresChange(filter:callback:) - newer API
        // 2. channel.on(event:callback:) - older API with string events
        // 3. Different filter/payload structures depending on version
        
        // For now, subscribe to channel (subscriptions will be added once API is confirmed)
        Task {
            do {
                try await channel.subscribe()
            } catch {
                onError?(error)
            }
        }
        
        subscriptions[recallId] = channel
    }
    
    // MARK: - Unsubscribe
    
    func unsubscribeFromRecall(recallId: UUID) {
        if let channel = subscriptions[recallId] {
            Task {
                await channel.unsubscribe()
            }
            subscriptions.removeValue(forKey: recallId)
        }
    }
    
    // MARK: - Unsubscribe All
    
    func unsubscribeAll() {
        Task { @MainActor in
            for (_, channel) in subscriptions {
                await channel.unsubscribe()
            }
            subscriptions.removeAll()
        }
    }
    
    deinit {
        Task { @MainActor in
            await unsubscribeAll()
        }
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















