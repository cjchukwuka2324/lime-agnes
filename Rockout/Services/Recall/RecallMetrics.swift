import Foundation

/// RecallMetrics tracks performance metrics for Recall operations
/// to enable monitoring and bottleneck identification at scale.
actor RecallMetrics {
    static let shared = RecallMetrics()
    
    private var operationDurations: [String: [TimeInterval]] = [:]
    private var errorCounts: [String: Int] = [:]
    private var requestCounts: [String: Int] = [:]
    private let maxMeasurements = 1000 // Keep last 1000 measurements per operation
    
    private init() {}
    
    // MARK: - Recording Metrics
    
    func recordOperation(_ operation: String, duration: TimeInterval) {
        if operationDurations[operation] == nil {
            operationDurations[operation] = []
        }
        operationDurations[operation]?.append(duration)
        
        // Keep only last maxMeasurements
        if let durations = operationDurations[operation],
           durations.count > maxMeasurements {
            operationDurations[operation] = Array(durations.suffix(maxMeasurements))
        }
    }
    
    func recordError(_ operation: String) {
        errorCounts[operation, default: 0] += 1
    }
    
    func recordRequest(_ operation: String) {
        requestCounts[operation, default: 0] += 1
    }
    
    // MARK: - Retrieving Stats
    
    func getStats(for operation: String) -> [String: Any]? {
        guard let durations = operationDurations[operation], !durations.isEmpty else {
            return nil
        }
        
        let sorted = durations.sorted()
        let count = sorted.count
        let p95Index = Int(Double(count) * 0.95)
        let p99Index = Int(Double(count) * 0.99)
        
        return [
            "avg_duration": durations.reduce(0, +) / Double(count),
            "min_duration": sorted.first ?? 0,
            "max_duration": sorted.last ?? 0,
            "p50_duration": sorted[count / 2],
            "p95_duration": sorted[min(p95Index, count - 1)],
            "p99_duration": sorted[min(p99Index, count - 1)],
            "count": count,
            "errors": errorCounts[operation] ?? 0,
            "requests": requestCounts[operation] ?? 0
        ]
    }
    
    func getAllStats() -> [String: [String: Any]] {
        var stats: [String: [String: Any]] = [:]
        
        for (operation, durations) in operationDurations {
            guard !durations.isEmpty else { continue }
            
            let sorted = durations.sorted()
            let count = sorted.count
            let p95Index = Int(Double(count) * 0.95)
            let p99Index = Int(Double(count) * 0.99)
            
            stats[operation] = [
                "avg_duration": durations.reduce(0, +) / Double(count),
                "min_duration": sorted.first ?? 0,
                "max_duration": sorted.last ?? 0,
                "p50_duration": sorted[count / 2],
                "p95_duration": sorted[min(p95Index, count - 1)],
                "p99_duration": sorted[min(p99Index, count - 1)],
                "count": count,
                "errors": errorCounts[operation] ?? 0,
                "requests": requestCounts[operation] ?? 0
            ]
        }
        
        return stats
    }
    
    func getSummary() -> [String: Any] {
        var totalRequests = 0
        var totalErrors = 0
        var totalOperations = 0
        
        for count in requestCounts.values {
            totalRequests += count
        }
        
        for count in errorCounts.values {
            totalErrors += count
        }
        
        for durations in operationDurations.values {
            totalOperations += durations.count
        }
        
        return [
            "total_requests": totalRequests,
            "total_errors": totalErrors,
            "total_operations": totalOperations,
            "error_rate": totalRequests > 0 ? Double(totalErrors) / Double(totalRequests) : 0.0,
            "operations": Array(operationDurations.keys)
        ]
    }
    
    // MARK: - Reset
    
    func reset() {
        operationDurations.removeAll()
        errorCounts.removeAll()
        requestCounts.removeAll()
    }
}






