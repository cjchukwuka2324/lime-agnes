import Foundation

/// ProfileCache provides TTL-based caching for user profiles to prevent N+1 queries.
/// Profiles are cached for 5 minutes and invalidated on updates.
///
/// This prevents every post card from independently fetching author profiles.
actor ProfileCache {
    static let shared = ProfileCache()
    
    private struct CachedProfile {
        let profile: UserProfileService.UserProfile
        let cachedAt: Date
    }
    
    private var cache: [String: CachedProfile] = [:] // userId -> CachedProfile
    private let ttl: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    /// Get a cached profile if available and not expired
    func get(userId: String) -> UserProfileService.UserProfile? {
        guard let cached = cache[userId] else {
            return nil
        }
        
        // Check if expired
        let age = Date().timeIntervalSince(cached.cachedAt)
        if age > ttl {
            cache.removeValue(forKey: userId)
            return nil
        }
        
        return cached.profile
    }
    
    /// Store a profile in the cache
    func set(userId: String, profile: UserProfileService.UserProfile) {
        cache[userId] = CachedProfile(profile: profile, cachedAt: Date())
    }
    
    /// Invalidate a specific profile (call after updates)
    func invalidate(userId: String) {
        cache.removeValue(forKey: userId)
    }
    
    /// Invalidate all profiles (call on logout or major changes)
    func invalidateAll() {
        cache.removeAll()
    }
    
    /// Get cache statistics (for debugging)
    func stats() -> (count: Int, oldestAge: TimeInterval?) {
        let now = Date()
        var oldestAge: TimeInterval?
        
        for cached in cache.values {
            let age = now.timeIntervalSince(cached.cachedAt)
            if oldestAge == nil || age > oldestAge! {
                oldestAge = age
            }
        }
        
        return (count: cache.count, oldestAge: oldestAge)
    }
    
    /// Clean up expired entries (call periodically)
    func cleanup() {
        let now = Date()
        let expiredKeys = cache.compactMap { (key, cached) -> String? in
            let age = now.timeIntervalSince(cached.cachedAt)
            return age > ttl ? key : nil
        }
        
        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }
    }
}



