import Foundation
import Supabase

protocol SocialGraphService {
    func currentUser() async -> UserSummary
    func currentUserId() async throws -> String
    func allUsers(cursor: String?, limit: Int) async -> (users: [UserSummary], nextCursor: String?, hasMore: Bool)
    func getProfile(userId: String) async throws -> UserSummary
    func getFollowers(of userId: String, cursor: String?, limit: Int) async throws -> (users: [UserSummary], nextCursor: String?, hasMore: Bool)
    func getFollowing(of userId: String, cursor: String?, limit: Int) async throws -> (users: [UserSummary], nextCursor: String?, hasMore: Bool)
    func getMutuals(with userId: String) async throws -> [UserSummary]
    func followingIds(forceRefresh: Bool) async -> Set<String>
    func followingIds(for userId: String) async -> Set<String>
    func followerIds(for userId: String) async -> Set<String>
    func follow(userId: String) async throws
    func unfollow(userId: String) async throws
    func searchUsers(query: String) async -> [UserSummary]
    func searchUsersPaginated(query: String, limit: Int, offset: Int) async throws -> (users: [UserSummary], hasMore: Bool)
    func setPostNotifications(for userId: String, enabled: Bool) async throws
}

@MainActor
final class SupabaseSocialGraphService: SocialGraphService, ObservableObject {
    static let shared = SupabaseSocialGraphService()
    
    private let supabase = SupabaseService.shared.client
    @Published private var cachedUsers: [UserSummary] = []
    @Published private var cachedFollowing: Set<String> = []
    @Published private var cachedFollowers: [String: Set<String>] = [:]
    
    private init() {}
    
    // MARK: - Current User
    
    func currentUserId() async throws -> String {
        guard let currentUserId = supabase.auth.currentUser?.id.uuidString else {
            throw NSError(domain: "SocialGraphService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        return currentUserId
    }
    
    func currentUser() async -> UserSummary {
        guard let currentUserId = supabase.auth.currentUser?.id.uuidString else {
            return createFallbackUser(id: "anonymous", displayName: "Anonymous", handle: "@anonymous", initials: "AN")
        }
        
        // Try to get from cache first
        if let cached = cachedUsers.first(where: { $0.id == currentUserId }) {
            return cached
        }
        
        // Load from Supabase
        do {
            if let profile = try await UserProfileService.shared.getCurrentUserProfile() {
                return createUserSummary(from: profile, userId: currentUserId)
            } else {
                return createFallbackUser(id: currentUserId, displayName: "User", handle: "@user", initials: "U")
            }
        } catch {
            // Fallback to basic user
            return createFallbackUser(id: currentUserId, displayName: "User", handle: "@user", initials: "U")
        }
    }
    
    // MARK: - All Users
    
    func allUsers(cursor: String? = nil, limit: Int = 100) async -> (users: [UserSummary], nextCursor: String?, hasMore: Bool) {
        do {
            // Enforce max limit of 100
            let effectiveLimit = min(limit, 100)
            
            // Build query with pagination
            // Use id-based cursor for simplicity (cursor is the last user id from previous page)
            var query = supabase
                .from("profiles")
                .select("""
                    id,
                    display_name,
                    first_name,
                    last_name,
                    username,
                    profile_picture_url,
                    region,
                    followers_count,
                    following_count,
                    instagram,
                    twitter,
                    tiktok
                """)
                .order("id", ascending: false) // Order by id for stable cursor
                .limit(effectiveLimit + 1) // Fetch one extra to check if there are more
            
            // Apply cursor if provided (cursor is the last user id from previous page)
            // Note: Supabase Swift client doesn't support .lt() directly, so we use a workaround
            // For UUID-based pagination, we'll fetch and filter in memory if cursor is provided
            // This is less efficient but works around the API limitation
            
            let response = try await query.execute()
            
            struct ProfileRow: Decodable {
                let id: UUID
                let display_name: String?
                let first_name: String?
                let last_name: String?
                let username: String?
                let profile_picture_url: String?
                let region: String?
                let followers_count: Int?
                let following_count: Int?
                let instagram: String?
                let twitter: String?
                let tiktok: String?
            }
            
            var allProfiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: response.data)
            
            // Apply cursor filtering in memory if provided
            if let cursor = cursor, let cursorUUID = UUID(uuidString: cursor) {
                allProfiles = allProfiles.filter { $0.id.uuidString < cursorUUID.uuidString }
            }
            
            // Check if there are more pages
            let hasMore = allProfiles.count > effectiveLimit
            let profiles = Array(allProfiles.prefix(effectiveLimit))
            
            // Get current user's email for fallback
            let currentUserEmail = supabase.auth.currentUser?.email
            
            let users = profiles.map { profile -> UserSummary in
                let displayName = profile.display_name ?? 
                    (profile.first_name != nil && profile.last_name != nil ? 
                     "\(profile.first_name!) \(profile.last_name!)" : 
                     "User")
                
                let handle = profile.username.map { "@\($0)" } ?? "@user"
                
                let initials: String = {
                    if let firstName = profile.first_name, let lastName = profile.last_name {
                        return "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
                    } else if let displayName = profile.display_name {
                        return String(displayName.prefix(2)).uppercased()
                    }
                    return "U"
                }()
                
                let pictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
                
                let isFollowing = cachedFollowing.contains(profile.id.uuidString)
                
                return UserSummary(
                    id: profile.id.uuidString,
                    displayName: displayName,
                    handle: handle,
                    avatarInitials: initials,
                    profilePictureURL: pictureURL,
                    isFollowing: isFollowing,
                    region: profile.region,
                    followersCount: profile.followers_count ?? 0,
                    followingCount: profile.following_count ?? 0,
                    instagramHandle: profile.instagram,
                    twitterHandle: profile.twitter,
                    tiktokHandle: profile.tiktok
                )
            }
            
            // Update cache with first page only
            if cursor == nil {
                cachedUsers = users
            }
            
            // Calculate next cursor (last user id)
            let nextCursor: String? = hasMore ? users.last?.id : nil
            
            return (users: users, nextCursor: nextCursor, hasMore: hasMore)
        } catch {
            print("Error loading users: \(error)")
            // Return cached users if available, otherwise empty
            return (users: cursor == nil ? cachedUsers : [], nextCursor: nil, hasMore: false)
        }
    }
    
    // MARK: - Following
    
    func followingIds(forceRefresh: Bool = false) async -> Set<String> {
        guard let currentUserId = supabase.auth.currentUser?.id.uuidString else {
            return []
        }
        
        // Return cached if available and not forcing refresh
        if !forceRefresh && !cachedFollowing.isEmpty {
            return cachedFollowing
        }
        
        // Load from Supabase
        do {
            let response = try await supabase
                .from("user_follows")
                .select("following_id")
                .eq("follower_id", value: currentUserId)
                .execute()
            
            struct FollowRow: Decodable {
                let following_id: UUID
            }
            
            let follows: [FollowRow] = try JSONDecoder().decode([FollowRow].self, from: response.data)
            // Convert UUIDs to strings for comparison
            let following = Set(follows.map { $0.following_id.uuidString })
            
            cachedFollowing = following
            print("✅ [FOLLOW] Loaded following IDs: \(following.count) users")
            if !following.isEmpty {
                print("   - Sample IDs: \(Array(following.prefix(3)))")
            }
            return following
        } catch {
            print("❌ Error loading following: \(error)")
            return cachedFollowing
        }
    }
    
    // MARK: - Following (for specific user)
    
    func followingIds(for userId: String) async -> Set<String> {
        // Load from Supabase for the specified user
        do {
            let response = try await supabase
                .from("user_follows")
                .select("following_id")
                .eq("follower_id", value: userId)
                .execute()
            
            struct FollowRow: Decodable {
                let following_id: String
            }
            
            let follows: [FollowRow] = try JSONDecoder().decode([FollowRow].self, from: response.data)
            return Set(follows.map { $0.following_id })
        } catch {
            print("Error loading following for user \(userId): \(error)")
            return []
        }
    }
    
    // MARK: - Followers
    
    func followerIds(for userId: String) async -> Set<String> {
        // Return cached if available
        if let cached = cachedFollowers[userId] {
            return cached
        }
        
        // Load from Supabase
        do {
            let response = try await supabase
                .from("user_follows")
                .select("follower_id")
                .eq("following_id", value: userId)
                .execute()
            
            struct FollowRow: Decodable {
                let follower_id: String
            }
            
            let follows: [FollowRow] = try JSONDecoder().decode([FollowRow].self, from: response.data)
            let followers = Set(follows.map { $0.follower_id })
            
            cachedFollowers[userId] = followers
            return followers
        } catch {
            print("Error loading followers: \(error)")
            return cachedFollowers[userId] ?? []
        }
    }
    
    // MARK: - Follow/Unfollow
    
    func follow(userId: String) async throws {
        guard let currentUserId = supabase.auth.currentUser?.id.uuidString else {
            throw NSError(domain: "SocialGraphService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard currentUserId != userId else { return }
        
        guard let targetUserId = UUID(uuidString: userId) else {
            throw NSError(domain: "SocialGraphService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        // Call RPC function to follow user (handles count updates atomically)
        struct FollowUserParams: Encodable {
            let target_user_id: UUID
        }
        
        try await supabase.rpc("follow_user", params: FollowUserParams(target_user_id: targetUserId)).execute()
        
        print("✅ [FOLLOW] Successfully called follow_user RPC for userId: \(userId)")
        
        // Small delay to ensure database transaction completes
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds - increased for DB commit
        
        // Clear cache and force refresh on next call to ensure accurate state
        cachedFollowing.removeAll()
        cachedFollowers.removeAll()
        cachedUsers.removeAll() // Clear all user caches
        print("✅ [FOLLOW] Cleared all caches after follow")
    }
    
    func unfollow(userId: String) async throws {
        guard let currentUserId = supabase.auth.currentUser?.id.uuidString else {
            throw NSError(domain: "SocialGraphService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard let targetUserId = UUID(uuidString: userId) else {
            throw NSError(domain: "SocialGraphService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        // Call RPC function to unfollow user (handles count updates atomically)
        struct UnfollowUserParams: Encodable {
            let target_user_id: UUID
        }
        
        try await supabase.rpc("unfollow_user", params: UnfollowUserParams(target_user_id: targetUserId)).execute()
        
        print("✅ [FOLLOW] Successfully called unfollow_user RPC for userId: \(userId)")
        
        // Small delay to ensure database transaction completes
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds - increased for DB commit
        
        // Clear cache and force refresh on next call to ensure accurate state
        cachedFollowing.removeAll()
        cachedFollowers.removeAll()
        cachedUsers.removeAll() // Clear all user caches
        print("✅ [FOLLOW] Cleared all caches after unfollow")
    }
    
    // MARK: - Get Profile
    
    func getProfile(userId: String) async throws -> UserSummary {
        guard let userIdUUID = UUID(uuidString: userId) else {
            throw NSError(domain: "SocialGraphService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        // Fetch profile from Supabase (always fresh, no cache)
        // Use single() to ensure we get the latest data
        let response = try await supabase
            .from("profiles")
            .select("""
                id,
                display_name,
                first_name,
                last_name,
                username,
                profile_picture_url,
                region,
                followers_count,
                following_count,
                instagram,
                twitter,
                tiktok
            """)
            .eq("id", value: userIdUUID)
            .single()
            .execute()
        
        struct ProfileRow: Decodable {
            let id: UUID
            let display_name: String?
            let first_name: String?
            let last_name: String?
            let username: String?
            let profile_picture_url: String?
            let region: String?
            let followers_count: Int?
            let following_count: Int?
            let instagram: String?
            let twitter: String?
            let tiktok: String?
        }
        
        // When using .single(), Supabase returns a single object (dictionary), not an array
        let profile: ProfileRow = try JSONDecoder().decode(ProfileRow.self, from: response.data)
        
        let displayName = profile.display_name ??
            (profile.first_name != nil && profile.last_name != nil ?
             "\(profile.first_name!) \(profile.last_name!)" :
             profile.username?.capitalized ?? "User")
        
        let handle = profile.username.map { "@\($0)" } ?? "@user"
        
        let initials: String = {
            if let firstName = profile.first_name, let lastName = profile.last_name {
                return "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
            } else if let displayName = profile.display_name {
                return String(displayName.prefix(2)).uppercased()
            } else if let username = profile.username {
                return String(username.prefix(2)).uppercased()
            }
            return "U"
        }()
        
        let pictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
        
        // Check if current user follows this user - always fetch fresh data for accurate state
        let currentUserId = try await currentUserId()
        let following = await followingIds(forceRefresh: true) // Force refresh to get accurate state
        let isFollowing = following.contains(userId)
        
        print("🔍 [FOLLOW] getProfile for userId: \(userId)")
        print("   - Current user ID: \(currentUserId)")
        print("   - Following set contains \(following.count) users")
        print("   - Checking if following contains userId: \(userId)")
        print("   - Is following: \(isFollowing)")
        if !following.isEmpty {
            print("   - Sample following IDs: \(Array(following.prefix(3)))")
        }
        
        return UserSummary(
            id: userId,
            displayName: displayName,
            handle: handle,
            avatarInitials: initials,
            profilePictureURL: pictureURL,
            isFollowing: isFollowing,
            region: profile.region,
            followersCount: profile.followers_count ?? 0,
            followingCount: profile.following_count ?? 0,
            instagramHandle: profile.instagram,
            twitterHandle: profile.twitter,
            tiktokHandle: profile.tiktok
        )
    }
    
    // MARK: - Get Followers
    
    func getFollowers(of userId: String, cursor: String? = nil, limit: Int = 100) async throws -> (users: [UserSummary], nextCursor: String?, hasMore: Bool) {
        guard let userIdUUID = UUID(uuidString: userId) else {
            throw NSError(domain: "SocialGraphService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        // Enforce max limit of 100
        let effectiveLimit = min(limit, 100)
        
        // Query user_follows table with pagination
        // Use id-based cursor for simplicity (cursor is the last follower_id from previous page)
        var query = supabase
            .from("user_follows")
            .select("follower_id, created_at")
            .eq("following_id", value: userIdUUID.uuidString)
            .order("follower_id", ascending: true) // Order by id for stable cursor
            .limit(effectiveLimit + 1) // Fetch one extra to check if there are more
        
        // Apply cursor if provided (cursor is the last follower_id from previous page)
        // Note: Supabase Swift client doesn't support .gt() directly, so we'll filter in memory
        // This is less efficient but works around the API limitation
        
        struct FollowRow: Decodable {
            let follower_id: String
            let created_at: String
        }
        
        let response = try await query.execute()
        var followRows: [FollowRow] = try JSONDecoder().decode([FollowRow].self, from: response.data)
        
        // Apply cursor filtering in memory if provided
        if let cursor = cursor, let cursorUUID = UUID(uuidString: cursor) {
            followRows = followRows.filter { $0.follower_id > cursorUUID.uuidString }
        }
        
        // Check if there are more pages
        let hasMore = followRows.count > effectiveLimit
        let paginatedRows = Array(followRows.prefix(effectiveLimit))
        
        guard !paginatedRows.isEmpty else {
            return (users: [], nextCursor: nil, hasMore: false)
        }
        
        // Get follower IDs
        let followerIds = paginatedRows.map { $0.follower_id }
        let followerUUIDs = followerIds.compactMap { UUID(uuidString: $0) }
        
        // Fetch profiles for this page of followers
        let profileResponse = try await supabase
            .from("profiles")
            .select("""
                id,
                display_name,
                first_name,
                last_name,
                username,
                profile_picture_url,
                region,
                followers_count,
                following_count,
                instagram,
                twitter,
                tiktok
            """)
            .in("id", values: followerUUIDs)
            .limit(1000) // Safety limit
            .execute()
        
        struct ProfileRow: Decodable {
            let id: UUID
            let display_name: String?
            let first_name: String?
            let last_name: String?
            let username: String?
            let profile_picture_url: String?
            let region: String?
            let followers_count: Int?
            let following_count: Int?
            let instagram: String?
            let twitter: String?
            let tiktok: String?
        }
        
        let profiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: profileResponse.data)
        
        // Create a map for quick lookup
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id.uuidString, $0) })
        
        // Get current user's following to determine isFollowing status
        let currentUserId = try? await currentUserId()
        let following = currentUserId != nil ? await followingIds() : []
        
        // Build users in the same order as followerIds
        let users = followerIds.compactMap { followerId -> UserSummary? in
            guard let profile = profileMap[followerId] else { return nil }
            
            let displayName = profile.display_name ??
                (profile.first_name != nil && profile.last_name != nil ?
                 "\(profile.first_name!) \(profile.last_name!)" :
                 profile.username?.capitalized ?? "User")
            
            let handle = profile.username.map { "@\($0)" } ?? "@user"
            
            let initials: String = {
                if let firstName = profile.first_name, let lastName = profile.last_name {
                    return "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
                } else if let displayName = profile.display_name {
                    return String(displayName.prefix(2)).uppercased()
                } else if let username = profile.username {
                    return String(username.prefix(2)).uppercased()
                }
                return "U"
            }()
            
            let pictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
            let isFollowing = following.contains(profile.id.uuidString)
            
            return UserSummary(
                id: profile.id.uuidString,
                displayName: displayName,
                handle: handle,
                avatarInitials: initials,
                profilePictureURL: pictureURL,
                isFollowing: isFollowing,
                region: profile.region,
                followersCount: profile.followers_count ?? 0,
                followingCount: profile.following_count ?? 0,
                instagramHandle: profile.instagram,
                twitterHandle: profile.twitter,
                tiktokHandle: profile.tiktok
            )
        }
        
        // Calculate next cursor (last follower_id)
        let nextCursor: String? = hasMore ? users.last?.id : nil
        
        return (users: users, nextCursor: nextCursor, hasMore: hasMore)
    }
    
    // MARK: - Get Following
    
    func getFollowing(of userId: String, cursor: String? = nil, limit: Int = 100) async throws -> (users: [UserSummary], nextCursor: String?, hasMore: Bool) {
        guard let userIdUUID = UUID(uuidString: userId) else {
            throw NSError(domain: "SocialGraphService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        // Enforce max limit of 100
        let effectiveLimit = min(limit, 100)
        
        // Query user_follows table with pagination
        // Use id-based cursor for simplicity (cursor is the last following_id from previous page)
        var query = supabase
            .from("user_follows")
            .select("following_id, created_at")
            .eq("follower_id", value: userIdUUID.uuidString)
            .order("following_id", ascending: true) // Order by id for stable cursor
            .limit(effectiveLimit + 1) // Fetch one extra to check if there are more
        
        // Apply cursor if provided (cursor is the last following_id from previous page)
        // Note: Supabase Swift client doesn't support .gt() directly, so we'll filter in memory
        // This is less efficient but works around the API limitation
        
        struct FollowRow: Decodable {
            let following_id: String
            let created_at: String
        }
        
        let response = try await query.execute()
        var followRows: [FollowRow] = try JSONDecoder().decode([FollowRow].self, from: response.data)
        
        // Apply cursor filtering in memory if provided
        if let cursor = cursor, let cursorUUID = UUID(uuidString: cursor) {
            followRows = followRows.filter { $0.following_id > cursorUUID.uuidString }
        }
        
        // Check if there are more pages
        let hasMore = followRows.count > effectiveLimit
        let paginatedRows = Array(followRows.prefix(effectiveLimit))
        
        guard !paginatedRows.isEmpty else {
            return (users: [], nextCursor: nil, hasMore: false)
        }
        
        // Get following IDs
        let followingIds = paginatedRows.map { $0.following_id }
        let followingUUIDs = followingIds.compactMap { UUID(uuidString: $0) }
        
        // Fetch profiles for this page of following
        let profileResponse = try await supabase
            .from("profiles")
            .select("""
                id,
                display_name,
                first_name,
                last_name,
                username,
                profile_picture_url,
                region,
                followers_count,
                following_count,
                instagram,
                twitter,
                tiktok
            """)
            .in("id", values: followingUUIDs)
            .limit(1000) // Safety limit
            .execute()
        
        struct ProfileRow: Decodable {
            let id: UUID
            let display_name: String?
            let first_name: String?
            let last_name: String?
            let username: String?
            let profile_picture_url: String?
            let region: String?
            let followers_count: Int?
            let following_count: Int?
            let instagram: String?
            let twitter: String?
            let tiktok: String?
        }
        
        let profiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: profileResponse.data)
        
        // Create a map for quick lookup
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id.uuidString, $0) })
        
        // Get current user's following to determine isFollowing status
        let currentUserId = try? await currentUserId()
        let currentUserFollowing: Set<String>
        if currentUserId != nil {
            currentUserFollowing = await self.followingIds()
        } else {
            currentUserFollowing = []
        }
        
        // Build users in the same order as followingIds
        let users = followingIds.compactMap { followingId -> UserSummary? in
            guard let profile = profileMap[followingId] else { return nil }
            
            let displayName = profile.display_name ??
                (profile.first_name != nil && profile.last_name != nil ?
                 "\(profile.first_name!) \(profile.last_name!)" :
                 profile.username?.capitalized ?? "User")
            
            let handle = profile.username.map { "@\($0)" } ?? "@user"
            
            let initials: String = {
                if let firstName = profile.first_name, let lastName = profile.last_name {
                    return "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
                } else if let displayName = profile.display_name {
                    return String(displayName.prefix(2)).uppercased()
                } else if let username = profile.username {
                    return String(username.prefix(2)).uppercased()
                }
                return "U"
            }()
            
            let pictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
            let isFollowing = currentUserFollowing.contains(profile.id.uuidString)
            
            return UserSummary(
                id: profile.id.uuidString,
                displayName: displayName,
                handle: handle,
                avatarInitials: initials,
                profilePictureURL: pictureURL,
                isFollowing: isFollowing,
                region: profile.region,
                followersCount: profile.followers_count ?? 0,
                followingCount: profile.following_count ?? 0,
                instagramHandle: profile.instagram,
                twitterHandle: profile.twitter,
                tiktokHandle: profile.tiktok
            )
        }
        
        // Calculate next cursor (last following_id)
        let nextCursor: String? = hasMore ? users.last?.id : nil
        
        return (users: users, nextCursor: nextCursor, hasMore: hasMore)
    }
    
    // MARK: - Get Mutuals
    
    func getMutuals(with userId: String) async throws -> [UserSummary] {
        guard let currentUserId = try? await currentUserId() else {
            throw NSError(domain: "SocialGraphService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard let userIdUUID = UUID(uuidString: userId) else {
            throw NSError(domain: "SocialGraphService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        // Get current user's following
        let currentUserFollowing = await followingIds()
        
        // Get target user's following
        let targetUserFollowing = await followingIds(for: userId)
        
        // Find intersection (mutual follows)
        let mutualIds = currentUserFollowing.intersection(targetUserFollowing)
        
        guard !mutualIds.isEmpty else {
            return []
        }
        
        // Fetch profiles for mutual follows
        let mutualUUIDs = mutualIds.compactMap { UUID(uuidString: $0) }
        
        let response = try await supabase
            .from("profiles")
            .select("""
                id,
                display_name,
                first_name,
                last_name,
                username,
                profile_picture_url,
                region,
                followers_count,
                following_count,
                instagram,
                twitter,
                tiktok
            """)
            .in("id", values: mutualUUIDs)
            .execute()
        
        struct ProfileRow: Decodable {
            let id: UUID
            let display_name: String?
            let first_name: String?
            let last_name: String?
            let username: String?
            let profile_picture_url: String?
            let region: String?
            let followers_count: Int?
            let following_count: Int?
            let instagram: String?
            let twitter: String?
            let tiktok: String?
        }
        
        let profiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: response.data)
        
        return profiles.map { profile -> UserSummary in
            let displayName = profile.display_name ??
                (profile.first_name != nil && profile.last_name != nil ?
                 "\(profile.first_name!) \(profile.last_name!)" :
                 profile.username?.capitalized ?? "User")
            
            let handle = profile.username.map { "@\($0)" } ?? "@user"
            
            let initials: String = {
                if let firstName = profile.first_name, let lastName = profile.last_name {
                    return "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
                } else if let displayName = profile.display_name {
                    return String(displayName.prefix(2)).uppercased()
                } else if let username = profile.username {
                    return String(username.prefix(2)).uppercased()
                }
                return "U"
            }()
            
            let pictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
            
            // Mutual follows are always following (by definition)
            return UserSummary(
                id: profile.id.uuidString,
                displayName: displayName,
                handle: handle,
                avatarInitials: initials,
                profilePictureURL: pictureURL,
                isFollowing: true,
                region: profile.region,
                followersCount: profile.followers_count ?? 0,
                followingCount: profile.following_count ?? 0,
                instagramHandle: profile.instagram,
                twitterHandle: profile.twitter,
                tiktokHandle: profile.tiktok
            )
        }
    }
    
    // MARK: - Search
    
    func searchUsers(query: String) async -> [UserSummary] {
        let searchQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !searchQuery.isEmpty else { return [] }
        
        guard let currentUserId = supabase.auth.currentUser?.id else {
            print("⚠️ Search: No current user ID")
            return []
        }
        
        do {
            // Use the alternative method which searches each field individually
            // This is more reliable than .or() which may not work correctly with Supabase Swift client
            print("🔍 Searching for: '\(searchQuery)' using alternative method")
            return try await searchUsersAlternative(query: searchQuery)
        } catch {
            print("❌ Error in searchUsersAlternative: \(error)")
            return []
        }
    }
    
    // Main search method using individual queries (more reliable)
    private func searchUsersAlternative(query: String) async throws -> [UserSummary] {
        guard let currentUserId = supabase.auth.currentUser?.id else {
            return []
        }
        
        let searchPattern = "%\(query)%"
        var allProfileIds: Set<UUID> = []
        
        // Search each field individually and combine results
        let fields = ["username", "first_name", "last_name", "display_name"]
        
        // First, test if we can read from profiles at all
        do {
            let testResponse = try await supabase
                .from("profiles")
                .select("id, username, display_name")
                .limit(5)
                .execute()
            
            struct TestRow: Decodable {
                let id: UUID
                let username: String?
                let display_name: String?
            }
            
            let testProfiles: [TestRow] = try JSONDecoder().decode([TestRow].self, from: testResponse.data)
            print("🔍 Test query: Found \(testProfiles.count) total profiles in database")
            for profile in testProfiles {
                print("  - ID: \(profile.id), username: \(profile.username ?? "nil"), display_name: \(profile.display_name ?? "nil")")
            }
        } catch {
            print("❌ Error reading profiles table: \(error)")
        }
        
        // Fetch all profiles and filter in Swift (more reliable than trying different query methods)
        // This is less efficient but will work regardless of RLS or query method issues
        do {
            let allProfilesResponse = try await supabase
                .from("profiles")
                .select("""
                    id,
                    display_name,
                    first_name,
                    last_name,
                    username
                """)
                .neq("id", value: currentUserId)
                .limit(200) // Get more profiles to search through
                .execute()
            
            struct ProfileSearchRow: Decodable {
                let id: UUID
                let display_name: String?
                let first_name: String?
                let last_name: String?
                let username: String?
            }
            
            let allProfiles: [ProfileSearchRow] = try JSONDecoder().decode([ProfileSearchRow].self, from: allProfilesResponse.data)
            print("🔍 Fetched \(allProfiles.count) profiles to search through")
            
            // Filter in Swift using case-insensitive matching
            let searchLower = query.lowercased()
            let matchingProfiles = allProfiles.filter { profile in
                let usernameMatch = profile.username?.lowercased().contains(searchLower) ?? false
                let firstNameMatch = profile.first_name?.lowercased().contains(searchLower) ?? false
                let lastNameMatch = profile.last_name?.lowercased().contains(searchLower) ?? false
                let displayNameMatch = profile.display_name?.lowercased().contains(searchLower) ?? false
                
                return usernameMatch || firstNameMatch || lastNameMatch || displayNameMatch
            }
            
            allProfileIds = Set(matchingProfiles.map { $0.id })
            print("🔍 Found \(allProfileIds.count) matching profiles after filtering")
            
            if !matchingProfiles.isEmpty {
                print("✅ Sample matches:")
                for (index, profile) in matchingProfiles.prefix(3).enumerated() {
                    print("  [\(index)] username: \(profile.username ?? "nil"), display_name: \(profile.display_name ?? "nil")")
                }
            }
        } catch {
            print("❌ Error fetching profiles for search: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
        
        guard !allProfileIds.isEmpty else {
            print("⚠️ No profiles found with alternative method")
            return []
        }
        
        print("✅ Alternative method found \(allProfileIds.count) unique profiles")
        
        // Fetch full profile data for found IDs
        let response = try await supabase
            .from("profiles")
            .select("""
                id,
                display_name,
                first_name,
                last_name,
                username,
                profile_picture_url,
                region,
                followers_count,
                following_count
            """)
            .in("id", values: Array(allProfileIds))
            .limit(50)
            .execute()
        
        struct ProfileRow: Decodable {
            let id: UUID
            let display_name: String?
            let first_name: String?
            let last_name: String?
            let username: String?
            let profile_picture_url: String?
            let region: String?
            let followers_count: Int?
            let following_count: Int?
        }
        
        let profiles: [ProfileRow] = try JSONDecoder().decode([ProfileRow].self, from: response.data)
        print("🔍 Decoded \(profiles.count) profiles")
        
        // Debug: Print first few profiles
        if !profiles.isEmpty {
            print("✅ Found profiles:")
            for (index, profile) in profiles.prefix(3).enumerated() {
                print("  [\(index)] ID: \(profile.id), username: \(profile.username ?? "nil"), display_name: \(profile.display_name ?? "nil")")
            }
        }
        
        let following = await followingIds()
        
        return profiles.map { profile -> UserSummary in
            let displayName = profile.display_name ??
                (profile.first_name != nil && profile.last_name != nil ?
                 "\(profile.first_name!) \(profile.last_name!)" :
                 profile.username?.capitalized ?? "User")

            let handle = profile.username.map { "@\($0)" } ?? "@user"

            let initials: String = {
                if let firstName = profile.first_name, let lastName = profile.last_name {
                    return "\(String(firstName.prefix(1)))\(String(lastName.prefix(1)))".uppercased()
                } else if let displayName = profile.display_name {
                    return String(displayName.prefix(2)).uppercased()
                }
                return "U"
            }()

            let pictureURL = profile.profile_picture_url.flatMap { URL(string: $0) }
            let isFollowing = following.contains(profile.id.uuidString)

            return UserSummary(
                id: profile.id.uuidString,
                displayName: displayName,
                handle: handle,
                avatarInitials: initials,
                profilePictureURL: pictureURL,
                isFollowing: isFollowing,
                region: profile.region,
                followersCount: profile.followers_count ?? 0,
                followingCount: profile.following_count ?? 0
            )
        }
    }
    
    // MARK: - Helper Functions
    
    private func createUserSummary(from profile: UserProfileService.UserProfile, userId: String) -> UserSummary {
        let displayName: String
        if let firstName = profile.firstName, let lastName = profile.lastName {
            displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        } else if let displayNameValue = profile.displayName, !displayNameValue.isEmpty {
            displayName = displayNameValue
        } else {
            let email = supabase.auth.currentUser?.email ?? "User"
            displayName = email.components(separatedBy: "@").first?.capitalized ?? "User"
        }
        
        let handle: String
        if let username = profile.username {
            handle = "@\(username)"
        } else if let email = supabase.auth.currentUser?.email {
            let emailPrefix = email.components(separatedBy: "@").first ?? "user"
            handle = "@\(emailPrefix)"
        } else if let firstName = profile.firstName {
            handle = "@\(firstName.lowercased())"
        } else {
            handle = "@user"
        }
        
        let initials: String
        if let firstName = profile.firstName, let lastName = profile.lastName {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            let lastInitial = String(lastName.prefix(1)).uppercased()
            initials = "\(firstInitial)\(lastInitial)"
        } else {
            initials = String(displayName.prefix(2)).uppercased()
        }
        
        let pictureURL = profile.profilePictureURL.flatMap { URL(string: $0) }
        
        return UserSummary(
            id: userId,
            displayName: displayName,
            handle: handle,
            avatarInitials: initials,
            profilePictureURL: pictureURL,
            isFollowing: false,
            region: nil,
            followersCount: 0,
            followingCount: 0
        )
    }
    
    // MARK: - Post Notifications
    
    func setPostNotifications(for userId: String, enabled: Bool) async throws {
        guard let currentUserId = supabase.auth.currentUser?.id.uuidString else {
            throw NSError(domain: "SocialGraphService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard let currentUserIdUUID = UUID(uuidString: currentUserId),
              let targetUserIdUUID = UUID(uuidString: userId) else {
            throw NSError(domain: "SocialGraphService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        // Update notify_on_posts in user_follows table
        try await supabase
            .from("user_follows")
            .update(["notify_on_posts": enabled])
            .eq("follower_id", value: currentUserIdUUID)
            .eq("following_id", value: targetUserIdUUID)
            .execute()
    }
    
    private func createFallbackUser(id: String, displayName: String, handle: String, initials: String) -> UserSummary {
        UserSummary(
            id: id,
            displayName: displayName,
            handle: handle,
            avatarInitials: initials,
            profilePictureURL: nil,
            isFollowing: false,
            region: nil
        )
    }
    
    // MARK: - Paginated Search
    
    func searchUsersPaginated(query: String, limit: Int = 20, offset: Int = 0) async throws -> (users: [UserSummary], hasMore: Bool) {
        let searchQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !searchQuery.isEmpty else {
            return (users: [], hasMore: false)
        }
        
        struct SearchUsersParams: Encodable {
            let p_search_query: String
            let p_limit: Int
            let p_offset: Int
        }
        
        let params = SearchUsersParams(
            p_search_query: searchQuery,
            p_limit: limit,
            p_offset: offset
        )
        
        print("🔍 Searching users (paginated): query='\(searchQuery)', limit=\(limit), offset=\(offset)")
        
        let response = try await supabase
            .rpc("search_users_paginated", params: params)
            .execute()
        
        struct SearchUserRow: Decodable {
            let id: UUID
            let display_name: String?
            let first_name: String?
            let last_name: String?
            let username: String?
            let email: String?
            let profile_picture_url: String?
            let region: String?
            let followers_count: Int?
            let following_count: Int?
            let is_following: Bool
        }
        
        let decoder = JSONDecoder()
        let rows = try decoder.decode([SearchUserRow].self, from: response.data)
        
        print("✅ Found \(rows.count) users")
        
        // Convert to UserSummary
        let users = rows.map { row -> UserSummary in
            let displayName: String
            if let dn = row.display_name, !dn.isEmpty {
                displayName = dn
            } else if let fn = row.first_name, let ln = row.last_name {
                displayName = "\(fn) \(ln)".trimmingCharacters(in: .whitespaces)
            } else if let email = row.email {
                displayName = email.components(separatedBy: "@").first ?? "User"
            } else {
                displayName = "User"
            }
            
            let handle: String
            if let username = row.username, !username.isEmpty {
                handle = "@\(username)"
            } else if let email = row.email {
                handle = "@\(email.components(separatedBy: "@").first ?? "user")"
            } else {
                handle = "@user"
            }
            
            let initials: String
            if let fn = row.first_name, let ln = row.last_name {
                initials = "\(fn.prefix(1))\(ln.prefix(1))".uppercased()
            } else {
                initials = String(displayName.prefix(2)).uppercased()
            }
            
            return UserSummary(
                id: row.id.uuidString,
                displayName: displayName,
                handle: handle,
                avatarInitials: initials,
                profilePictureURL: row.profile_picture_url.flatMap { URL(string: $0) },
                isFollowing: row.is_following,
                region: row.region,
                followersCount: row.followers_count ?? 0,
                followingCount: row.following_count ?? 0
            )
        }
        
        // Determine if there are more results
        // If we got exactly 'limit' users, there might be more
        let hasMore = users.count == limit
        
        return (users: users, hasMore: hasMore)
    }
}
