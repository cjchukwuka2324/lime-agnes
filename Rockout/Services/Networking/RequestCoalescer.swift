import Foundation

/// RequestCoalescer ensures that identical concurrent requests are deduplicated.
/// If multiple callers request the same resource simultaneously, only one network call is made.
/// Other callers await the same Task/result.
///
/// This prevents request storms when thousands of users open the same screen simultaneously.
actor RequestCoalescer {
    static let shared = RequestCoalescer()
    
    // Type-erased task storage using continuations
    private struct CoalescedRequest {
        let getResult: () async throws -> Any
        let cancel: () -> Void
        
        init<T>(_ task: Task<T, Error>) {
            self.getResult = {
                return try await task.value
            }
            self.cancel = {
                task.cancel()
            }
        }
    }
    
    private var inflightRequests: [String: CoalescedRequest] = [:]
    
    private init() {}
    
    /// Execute a request with coalescing. If an identical request is already in flight,
    /// returns the existing task's result instead of making a new request.
    ///
    /// - Parameters:
    ///   - key: Unique identifier for the request (e.g., "feed:forYou:nil" or "profile:userId")
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: Any error thrown by the operation
    func execute<T: Sendable>(
        key: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        // Check if request is already in flight
        if let existingRequest = inflightRequests[key] {
            // Try to get the result and cast it to the expected type
            do {
                let anyResult = try await existingRequest.getResult()
                if let result = anyResult as? T {
                return result
            } else {
                    // Type mismatch - this shouldn't happen if keys are unique per type
                    // But if it does, remove and retry
                    inflightRequests.removeValue(forKey: key)
                }
            } catch {
                // Task failed, remove and retry
                inflightRequests.removeValue(forKey: key)
                throw error
            }
        }
        
        // Create new task
        let task = Task {
            do {
                let result = try await operation()
                // Remove from inflight when done
                await self.removeRequest(key: key)
                return result
            } catch {
                // Remove from inflight on error
                await self.removeRequest(key: key)
                throw error
            }
        }
        
        // Store as type-erased request
        inflightRequests[key] = CoalescedRequest(task)
        
        // Await the task and return result
        return try await task.value
    }
    
    /// Remove a request from the inflight map
    private func removeRequest(key: String) {
        inflightRequests.removeValue(forKey: key)
    }
    
    /// Cancel a specific request by key
    func cancel(key: String) {
        if let request = inflightRequests[key] {
            request.cancel()
            inflightRequests.removeValue(forKey: key)
        }
    }
    
    /// Cancel all inflight requests (useful for cleanup)
    func cancelAll() {
        for (_, request) in inflightRequests {
            request.cancel()
        }
        inflightRequests.removeAll()
    }
    
    /// Get count of inflight requests (for debugging)
    func inflightCount() -> Int {
        return inflightRequests.count
    }
}
