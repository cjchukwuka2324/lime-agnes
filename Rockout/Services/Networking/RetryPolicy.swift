import Foundation

/// RetryPolicy provides exponential backoff with jitter for retrying transient failures.
/// Only retries reads (GET requests), never writes, to avoid duplicate operations.
///
/// Retries up to 3 times with exponential backoff: 1s, 2s, 4s (plus jitter)
enum RetryPolicy {
    case noRetry
    case retryReads(maxAttempts: Int = 3, baseDelay: TimeInterval = 1.0)
    
    /// Determine if a request should be retried based on error type
    static func shouldRetry(error: Error, isRead: Bool) -> Bool {
        guard isRead else {
            // Never retry writes
            return false
        }
        
        // Check for transient errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost:
                return true
            case .httpTooManyRedirects:
                return true
            default:
                return false
            }
        }
        
        // Check for HTTP 429 (rate limit) or 5xx (server errors)
        if let httpError = error as? HTTPError {
            let statusCode = httpError.statusCode
            return statusCode == 429 || (statusCode >= 500 && statusCode < 600)
        }
        
        // Check for Supabase-specific errors that indicate transient failures
        let errorString = error.localizedDescription.lowercased()
        if errorString.contains("timeout") ||
           errorString.contains("network") ||
           errorString.contains("connection") ||
           errorString.contains("429") ||
           errorString.contains("rate limit") {
            return true
        }
        
        return false
    }
    
    /// Calculate delay for retry attempt with exponential backoff and jitter
    static func delayForAttempt(_ attempt: Int, baseDelay: TimeInterval = 1.0) -> TimeInterval {
        // Exponential backoff: baseDelay * 2^(attempt-1)
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        
        // Add jitter: random value between 0 and 25% of delay
        let jitterRange = exponentialDelay * 0.25
        let jitter = Double.random(in: 0...jitterRange)
        
        return exponentialDelay + jitter
    }
    
    /// Execute an operation with retry logic
    static func executeWithRetry<T>(
        isRead: Bool,
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Check if we should retry
                guard attempt < maxAttempts, shouldRetry(error: error, isRead: isRead) else {
                    throw error
                }
                
                // Calculate delay and wait
                let delay = delayForAttempt(attempt, baseDelay: baseDelay)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                
                // Continue to next attempt
            }
        }
        
        // Should never reach here, but throw last error if we do
        throw lastError ?? NSError(domain: "RetryPolicy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Retry exhausted"])
    }
}

/// Simple HTTPError for checking status codes
struct HTTPError: Error {
    let statusCode: Int
    let message: String?
    
    init(statusCode: Int, message: String? = nil) {
        self.statusCode = statusCode
        self.message = message
    }
}








