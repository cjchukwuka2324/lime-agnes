import Foundation

// MARK: - In-Memory Implementation (Deprecated - Use SupabaseSocialGraphService)

@MainActor
final class InMemorySocialGraphService {
    static let shared = InMemorySocialGraphService()
    
    private var following: Set<String> = []
    private var followersByUser: [String: Set<String>] = [:]
    private var users: [UserSummary] = []
    private let lock = NSLock()
    
    private init() {
        seedDemoUsers()
    }
    
    // MARK: - Current User
    
    func currentUser() -> UserSummary {
        // Get current user from Supabase if available, otherwise use demo user
        if let currentUserId = SupabaseService.shared.client.auth.currentUser?.id.uuidString {
            // Try to find user in our list
            if let user = users.first(where: { $0.id == currentUserId }) {
                return user
            }
            // Create a user summary from profile if available
            Task {
                if let profile = try? await UserProfileService.shared.getCurrentUserProfile() {
                    let displayName: String
                    if let firstName = profile.firstName, let lastName = profile.lastName {
                        displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                    } else if let displayNameValue = profile.displayName, !displayNameValue.isEmpty {
                        displayName = displayNameValue
                    } else {
                        let email = SupabaseService.shared.client.auth.currentUser?.email ?? "User"
                        displayName = email.components(separatedBy: "@").first ?? "User"
                    }
                    
                    let handle: String
                    if let username = profile.username {
                        handle = "@\(username)"
                    } else if let email = SupabaseService.shared.client.auth.currentUser?.email {
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
                    
                    let pictureURL: URL? = {
                        if let pictureURLString = profile.profilePictureURL, let url = URL(string: pictureURLString) {
                            return url
                        }
                        return nil
                    }()
                    
                    let user = UserSummary(
                        id: currentUserId,
                        displayName: displayName,
                        handle: handle,
                        avatarInitials: initials,
                        profilePictureURL: pictureURL,
                        isFollowing: false
                    )
                    
                    lock.lock()
                    defer { lock.unlock() }
                    
                    if let index = users.firstIndex(where: { $0.id == currentUserId }) {
                        users[index] = user
                    } else {
                        users.append(user)
                    }
                }
            }
        }
        
        // Return demo user as fallback
        return users.first ?? createDemoUser(id: "demo-user", displayName: "Demo User", handle: "@demo", initials: "DU")
    }
    
    // MARK: - All Users
    
    func allUsers() -> [UserSummary] {
        lock.lock()
        defer { lock.unlock() }
        
        let currentUserId = currentUser().id
        return users.map { user in
            return UserSummary(
                id: user.id,
                displayName: user.displayName,
                handle: user.handle,
                avatarInitials: user.avatarInitials,
                profilePictureURL: user.profilePictureURL,
                isFollowing: following.contains(user.id),
                region: user.region,
                followersCount: user.followersCount,
                followingCount: user.followingCount
            )
        }
    }
    
    // MARK: - Following
    
    func followingIds() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return following
    }
    
    // MARK: - Followers
    
    func followerIds(for userId: String) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return followersByUser[userId] ?? []
    }
    
    // MARK: - Follow/Unfollow
    
    func follow(userId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let currentUserId = currentUser().id
        guard currentUserId != userId else { return }
        
        following.insert(userId)
        
        if followersByUser[userId] == nil {
            followersByUser[userId] = []
        }
        followersByUser[userId]?.insert(currentUserId)
        
        // Update user's isFollowing status
        if let index = users.firstIndex(where: { $0.id == userId }) {
            let user = users[index]
            users[index] = UserSummary(
                id: user.id,
                displayName: user.displayName,
                handle: user.handle,
                avatarInitials: user.avatarInitials,
                profilePictureURL: user.profilePictureURL,
                isFollowing: true,
                region: user.region,
                followersCount: user.followersCount,
                followingCount: user.followingCount
            )
        }
    }
    
    func unfollow(userId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let currentUserId = currentUser().id
        following.remove(userId)
        followersByUser[userId]?.remove(currentUserId)
        
        // Update user's isFollowing status
        if let index = users.firstIndex(where: { $0.id == userId }) {
            let user = users[index]
            users[index] = UserSummary(
                id: user.id,
                displayName: user.displayName,
                handle: user.handle,
                avatarInitials: user.avatarInitials,
                profilePictureURL: user.profilePictureURL,
                isFollowing: false,
                region: user.region,
                followersCount: user.followersCount,
                followingCount: user.followingCount
            )
        }
    }
    
    // MARK: - Search
    
    func searchUsers(query: String) -> [UserSummary] {
        lock.lock()
        defer { lock.unlock() }
        
        let searchQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !searchQuery.isEmpty else { return [] }
        
        let currentUserId = currentUser().id
        return users.filter { user in
            guard user.id != currentUserId else { return false }
            return user.displayName.lowercased().contains(searchQuery) ||
                   user.handle.lowercased().contains(searchQuery)
        }.map { user in
            return UserSummary(
                id: user.id,
                displayName: user.displayName,
                handle: user.handle,
                avatarInitials: user.avatarInitials,
                profilePictureURL: user.profilePictureURL,
                isFollowing: following.contains(user.id),
                region: user.region,
                followersCount: user.followersCount,
                followingCount: user.followingCount
            )
        }
    }
    
    // MARK: - Demo Data
    
    private func seedDemoUsers() {
        let demoUsers = [
            createDemoUser(id: "user-1", displayName: "Alex Johnson", handle: "@alex", initials: "AJ"),
            createDemoUser(id: "user-2", displayName: "Sam Smith", handle: "@sam", initials: "SS"),
            createDemoUser(id: "user-3", displayName: "Jordan Lee", handle: "@jordan", initials: "JL"),
            createDemoUser(id: "user-4", displayName: "Taylor Swift", handle: "@taylor", initials: "TS"),
            createDemoUser(id: "user-5", displayName: "Chris Brown", handle: "@chris", initials: "CB")
        ]
        
        lock.lock()
        defer { lock.unlock() }
        users = demoUsers
        
        // Seed some follow relationships
        // Current user follows user-1 and user-2
        if let currentUserId = SupabaseService.shared.client.auth.currentUser?.id.uuidString {
            following.insert("user-1")
            following.insert("user-2")
            followersByUser["user-1"] = [currentUserId]
            followersByUser["user-2"] = [currentUserId]
        } else {
            // Demo mode: demo-user follows user-1 and user-2
            following.insert("user-1")
            following.insert("user-2")
            followersByUser["user-1"] = ["demo-user"]
            followersByUser["user-2"] = ["demo-user"]
        }
    }
    
    private func createDemoUser(id: String, displayName: String, handle: String, initials: String) -> UserSummary {
        UserSummary(
            id: id,
            displayName: displayName,
            handle: handle,
            avatarInitials: initials,
            profilePictureURL: nil,
            isFollowing: false
        )
    }
}


