import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebasePerformance)
import FirebasePerformance
#endif

/// Lightweight performance metrics for monitoring app performance at scale.
/// Tracks durations and counts without any PII (Personally Identifiable Information).
actor PerformanceMetrics {
    static let shared = PerformanceMetrics()
    
    private struct Metric {
        let name: String
        let duration: TimeInterval
        let timestamp: Date
        let metadata: [String: String]?
    }
    
    private var metrics: [Metric] = []
    private let maxMetrics = 1000 // Keep last 1000 metrics
    
    private init() {}
    
    /// Record a performance metric
    /// - Parameters:
    ///   - name: Name of the metric (e.g., "feed_load", "profile_fetch")
    ///   - duration: Duration in seconds
    ///   - metadata: Optional metadata (no PII allowed)
    func record(name: String, duration: TimeInterval, metadata: [String: String]? = nil) {
        let metric = Metric(
            name: name,
            duration: duration,
            timestamp: Date(),
            metadata: metadata
        )
        metrics.append(metric)
        
        // Trim if needed
        if metrics.count > maxMetrics {
            metrics.removeFirst(metrics.count - maxMetrics)
        }
        
        Logger.performance.info("\(name): \(String(format: "%.3f", duration))s")
    }
    
    /// Get statistics for a specific metric
    func stats(for name: String) -> (count: Int, avgDuration: TimeInterval, minDuration: TimeInterval, maxDuration: TimeInterval)? {
        let filtered = metrics.filter { $0.name == name }
        guard !filtered.isEmpty else { return nil }
        
        let durations = filtered.map { $0.duration }
        let avg = durations.reduce(0, +) / Double(durations.count)
        let min = durations.min() ?? 0
        let max = durations.max() ?? 0
        
        return (count: filtered.count, avgDuration: avg, minDuration: min, maxDuration: max)
    }
    
    /// Get all metrics (for debugging/export)
    func allMetrics() -> [(name: String, duration: TimeInterval, timestamp: Date, metadata: [String: String]?)] {
        return metrics.map { (name: $0.name, duration: $0.duration, timestamp: $0.timestamp, metadata: $0.metadata) }
    }
    
    /// Clear all metrics
    func clear() {
        metrics.removeAll()
    }
    
    /// Get summary statistics
    func summary() -> [String: (count: Int, avgDuration: TimeInterval)] {
        var summary: [String: (count: Int, totalDuration: TimeInterval)] = [:]
        
        for metric in metrics {
            if let existing = summary[metric.name] {
                summary[metric.name] = (count: existing.count + 1, totalDuration: existing.totalDuration + metric.duration)
            } else {
                summary[metric.name] = (count: 1, totalDuration: metric.duration)
            }
        }
        
        return summary.mapValues { (count: $0.count, avgDuration: $0.totalDuration / Double($0.count)) }
    }
}

/// Helper function to measure execution time of an async operation
func measureAsync<T>(_ name: String, operation: () async throws -> T) async rethrows -> T {
    let startTime = Date()
    defer {
        let duration = Date().timeIntervalSince(startTime)
        Task {
            await PerformanceMetrics.shared.record(name: name, duration: duration)
        }
    }
    return try await operation()
}

/// Helper function to measure execution time of a sync operation
func measureSync<T>(_ name: String, operation: () throws -> T) rethrows -> T {
    let startTime = Date()
    defer {
        let duration = Date().timeIntervalSince(startTime)
        Task {
            await PerformanceMetrics.shared.record(name: name, duration: duration)
        }
    }
    return try operation()
}

