import Foundation
import OSLog
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

/// Production-ready logging system using OSLog with Firebase Crashlytics integration
struct Logger {
    // MARK: - Subsystems
    
    static let networking = Logger(subsystem: "com.suinoik.rockout.networking", category: "Networking")
    static let ui = Logger(subsystem: "com.suinoik.rockout.ui", category: "UI")
    static let auth = Logger(subsystem: "com.suinoik.rockout.auth", category: "Authentication")
    static let feed = Logger(subsystem: "com.suinoik.rockout.feed", category: "Feed")
    static let profile = Logger(subsystem: "com.suinoik.rockout.profile", category: "Profile")
    static let recall = Logger(subsystem: "com.suinoik.rockout.recall", category: "Recall")
    static let spotify = Logger(subsystem: "com.suinoik.rockout.spotify", category: "Spotify")
    static let notifications = Logger(subsystem: "com.suinoik.rockout.notifications", category: "Notifications")
    static let cache = Logger(subsystem: "com.suinoik.rockout.cache", category: "Cache")
    static let performance = Logger(subsystem: "com.suinoik.rockout.performance", category: "Performance")
    static let general = Logger(subsystem: "com.suinoik.rockout", category: "General")
    
    // MARK: - Properties
    
    private let osLogger: OSLog
    private let subsystem: String
    private let category: String
    
    // MARK: - Initialization
    
    private init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        self.osLogger = OSLog(subsystem: subsystem, category: category)
    }
    
    // MARK: - Logging Methods
    
    /// Log a debug message (only in debug builds)
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        os_log("%{public}@", log: osLogger, type: .debug, logMessage)
        #endif
    }
    
    /// Log an info message
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        os_log("%{public}@", log: osLogger, type: .info, logMessage)
    }
    
    /// Log a warning message
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        os_log("%{public}@", log: osLogger, type: .default, logMessage)
    }
    
    /// Log an error message and send to Crashlytics
    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        os_log("%{public}@", log: osLogger, type: .error, logMessage)
        
        // Send to Firebase Crashlytics if available
        #if canImport(FirebaseCrashlytics)
        if let error = error {
            Crashlytics.crashlytics().record(error: error)
            Crashlytics.crashlytics().log("\(logMessage) - Error: \(error.localizedDescription)")
        } else {
            let nsError = NSError(domain: "com.suinoik.rockout", code: -1, userInfo: [
                NSLocalizedDescriptionKey: message,
                "file": fileName,
                "function": function,
                "line": line
            ])
            Crashlytics.crashlytics().record(error: nsError)
            Crashlytics.crashlytics().log(logMessage)
        }
        #endif
    }
    
    /// Log a fault (critical error)
    func fault(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function) - \(message)"
        os_log("%{public}@", log: osLogger, type: .fault, logMessage)
        
        // Send to Firebase Crashlytics
        #if canImport(FirebaseCrashlytics)
        if let error = error {
            Crashlytics.crashlytics().record(error: error)
            Crashlytics.crashlytics().log("FAULT: \(logMessage) - Error: \(error.localizedDescription)")
        } else {
            let nsError = NSError(domain: "com.suinoik.rockout", code: -2, userInfo: [
                NSLocalizedDescriptionKey: message,
                "file": fileName,
                "function": function,
                "line": line
            ])
            Crashlytics.crashlytics().record(error: nsError)
            Crashlytics.crashlytics().log("FAULT: \(logMessage)")
        }
        #endif
    }
    
    // MARK: - Convenience Methods
    
    /// Log success (info level with success indicator)
    func success(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        info("✅ \(message)", file: file, function: function, line: line)
    }
    
    /// Log failure (error level)
    func failure(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        self.error("❌ \(message)", error: error, file: file, function: function, line: line)
    }
}



