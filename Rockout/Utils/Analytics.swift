import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

/// Analytics wrapper for Firebase Analytics integration
/// Provides type-safe event logging and screen tracking
struct Analytics {
    
    // MARK: - Screen Tracking
    
    /// Log a screen view
    static func logScreenView(_ screenName: String, screenClass: String? = nil) {
        #if canImport(FirebaseAnalytics)
        var parameters: [String: Any] = [
            AnalyticsParameterScreenName: screenName
        ]
        if let screenClass = screenClass {
            parameters[AnalyticsParameterScreenClass] = screenClass
        }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)
        #endif
        Logger.general.debug("Screen view: \(screenName)")
    }
    
    // MARK: - User Events
    
    /// Log feed loaded event
    static func logFeedLoaded(feedType: String, postCount: Int, loadTime: TimeInterval) {
        logEvent("feed_loaded", parameters: [
            "feed_type": feedType,
            "post_count": postCount,
            "load_time_seconds": loadTime
        ])
    }
    
    /// Log post liked
    static func logPostLiked(postId: String) {
        logEvent("post_liked", parameters: ["post_id": postId])
    }
    
    /// Log post replied
    static func logPostReplied(postId: String, parentPostId: String) {
        logEvent("post_replied", parameters: [
            "post_id": postId,
            "parent_post_id": parentPostId
        ])
    }
    
    /// Log user followed
    static func logUserFollowed(userId: String) {
        logEvent("user_followed", parameters: ["user_id": userId])
    }
    
    /// Log user unfollowed
    static func logUserUnfollowed(userId: String) {
        logEvent("user_unfollowed", parameters: ["user_id": userId])
    }
    
    /// Log post created
    static func logPostCreated(hasImages: Bool, hasVideo: Bool, hasAudio: Bool, hasSpotifyLink: Bool, hasPoll: Bool) {
        logEvent("post_created", parameters: [
            "has_images": hasImages,
            "has_video": hasVideo,
            "has_audio": hasAudio,
            "has_spotify_link": hasSpotifyLink,
            "has_poll": hasPoll
        ])
    }
    
    /// Log error occurred
    static func logErrorOccurred(errorType: String, errorMessage: String, context: String? = nil) {
        var parameters: [String: Any] = [
            "error_type": errorType,
            "error_message": errorMessage
        ]
        if let context = context {
            parameters["context"] = context
        }
        logEvent("error_occurred", parameters: parameters)
    }
    
    /// Log performance metric
    static func logPerformanceMetric(operation: String, duration: TimeInterval, success: Bool) {
        logEvent("performance_metric", parameters: [
            "operation": operation,
            "duration_seconds": duration,
            "success": success
        ])
    }
    
    // MARK: - Generic Event Logging
    
    /// Log a custom event
    static func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        #if canImport(FirebaseAnalytics)
        if let parameters = parameters {
            Analytics.logEvent(name, parameters: parameters)
        } else {
            Analytics.logEvent(name, parameters: nil)
        }
        #endif
        Logger.general.debug("Analytics event: \(name)")
    }
    
    // MARK: - User Properties
    
    /// Set a user property
    static func setUserProperty(_ value: String?, forName name: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.setUserProperty(value, forName: name)
        #endif
        Logger.general.debug("User property set: \(name) = \(value ?? "nil")")
    }
    
    /// Set user ID for analytics
    static func setUserId(_ userId: String?) {
        #if canImport(FirebaseAnalytics)
        Analytics.setUserID(userId)
        #endif
        Logger.general.debug("User ID set: \(userId ?? "nil")")
    }
    
    // MARK: - Convenience Methods
    
    /// Log authentication event
    static func logAuthentication(method: String, success: Bool) {
        logEvent("authentication", parameters: [
            "method": method,
            "success": success
        ])
    }
    
    /// Log search performed
    static func logSearch(query: String, resultCount: Int) {
        logEvent("search_performed", parameters: [
            "query": query,
            "result_count": resultCount
        ])
    }
    
    /// Log profile viewed
    static func logProfileViewed(userId: String, isOwnProfile: Bool) {
        logEvent("profile_viewed", parameters: [
            "user_id": userId,
            "is_own_profile": isOwnProfile
        ])
    }
}








