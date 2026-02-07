import Foundation

/// Environment-aware application configuration
enum AppEnvironment {
    case development
    case staging
    case production
    
    static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        // In production builds, check for staging flag or use production
        if ProcessInfo.processInfo.environment["APP_ENV"] == "staging" {
            return .staging
        }
        return .production
        #endif
    }
    
    var name: String {
        switch self {
        case .development: return "development"
        case .staging: return "staging"
        case .production: return "production"
        }
    }
}

/// Application configuration based on environment
struct AppConfig {
    static let environment = AppEnvironment.current
    
    // MARK: - Feature Flags
    
    /// Whether Firebase is enabled (disabled in development for faster iteration)
    static let firebaseEnabled: Bool = {
        switch environment {
        case .development:
            return false // Disable in dev to avoid noise
        case .staging, .production:
            return true
        }
    }()
    
    /// Whether to enable verbose logging
    static let verboseLogging: Bool = {
        switch environment {
        case .development:
            return true
        case .staging, .production:
            return false
        }
    }()
    
    /// Whether to enable performance monitoring
    static let performanceMonitoringEnabled: Bool = {
        switch environment {
        case .development:
            return false
        case .staging, .production:
            return true
        }
    }()
    
    // MARK: - API Configuration
    
    /// Supabase URL based on environment
    static var supabaseUrl: String {
        switch environment {
        case .development:
            // Use same URL for now, but could be different
            return Secrets.supabaseUrl
        case .staging:
            // Could use staging Supabase instance
            return Secrets.supabaseUrl
        case .production:
            return Secrets.supabaseUrl
        }
    }
    
    /// Supabase anon key based on environment
    static var supabaseAnonKey: String {
        switch environment {
        case .development, .staging, .production:
            return Secrets.supabaseAnonKey
        }
    }
    
    // MARK: - Debug Info
    
    static var debugInfo: String {
        return """
        Environment: \(environment.name)
        Firebase Enabled: \(firebaseEnabled)
        Verbose Logging: \(verboseLogging)
        Performance Monitoring: \(performanceMonitoringEnabled)
        """
    }
}








