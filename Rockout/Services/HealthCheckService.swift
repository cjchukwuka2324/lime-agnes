import Foundation
import Network

/// Service for monitoring app health and connectivity
actor HealthCheckService {
    static let shared = HealthCheckService()
    
    private let monitor = NWPathMonitor()
    private var isMonitoring = false
    private var networkStatus: NWPath.Status = .requiresConnection
    
    private init() {
        startMonitoring()
    }
    
    /// Start monitoring network connectivity
    private func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                await self?.updateNetworkStatus(path.status)
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    /// Update network status
    private func updateNetworkStatus(_ status: NWPath.Status) {
        networkStatus = status
        Logger.networking.debug("Network status updated: \(status == .satisfied ? "connected" : "disconnected")")
    }
    
    /// Check if device is connected to network
    func isConnected() -> Bool {
        return networkStatus == .satisfied
    }
    
    /// Check Supabase connection health
    func checkSupabaseConnection() async -> Bool {
        do {
            let supabase = SupabaseService.shared.client
            // Try a simple query to check connection
            _ = try await supabase.auth.session
            return true
        } catch {
            Logger.networking.warning("Supabase connection check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Get comprehensive health status
    func getHealthStatus() async -> HealthStatus {
        let networkConnected = isConnected()
        let supabaseConnected = await checkSupabaseConnection()
        
        return HealthStatus(
            networkConnected: networkConnected,
            supabaseConnected: supabaseConnected,
            timestamp: Date()
        )
    }
}

/// Health status information
struct HealthStatus {
    let networkConnected: Bool
    let supabaseConnected: Bool
    let timestamp: Date
    
    var isHealthy: Bool {
        return networkConnected && supabaseConnected
    }
}



