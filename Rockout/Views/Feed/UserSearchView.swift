import SwiftUI
import Supabase

struct UserSearchView: View {
    @State private var searchText = ""
    @State private var searchResults: [UserProfileCard] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    private let profileService = UserProfileService.shared
    private let followService = FollowService.shared
    private let supabase = SupabaseService.shared.client
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Green gradient background
                LinearGradient(
                    colors: [
                        Color(hex: "#050505"),
                        Color(hex: "#0C7C38"),
                        Color(hex: "#1DB954"),
                        Color(hex: "#1ED760"),
                        Color(hex: "#050505")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("Search users...", text: $searchText)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: searchText) { _, newValue in
                                if newValue.isEmpty {
                                    searchResults = []
                                } else {
                                    Task {
                                        await searchUsers(query: newValue)
                                    }
                                }
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults = []
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.15))
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Results
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Text("Searching...")
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top)
                        Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .padding()
                        Spacer()
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        Spacer()
                        Text("No users found")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                    } else if searchResults.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.6))
                            Text("Search for users")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Find and follow other music lovers")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(searchResults) { user in
                                    UserProfileCardView(user: user)
                                        .padding(.horizontal, 20)
                                }
                            }
                            .padding(.vertical, 20)
                        }
                    }
                }
            }
            .navigationTitle("Search Users")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
    
    private func searchUsers(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            guard let currentUserId = supabase.auth.currentUser?.id else {
                throw NSError(domain: "UserSearchView", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
            }
            
            // Search profiles by first name, last name, or display name
            let searchQuery = query.trimmingCharacters(in: .whitespaces).lowercased()
            
            struct ProfileRow: Codable {
                let id: UUID
                let display_name: String?
                let first_name: String?
                let last_name: String?
            }
            
            let allProfiles: [ProfileRow] = try await supabase
                .from("profiles")
                .select("id, display_name, first_name, last_name")
                .neq("id", value: currentUserId)
                .execute()
                .value
            
            let matchingProfiles = allProfiles.filter { profile in
                let displayName = (profile.display_name ?? "").lowercased()
                let firstName = (profile.first_name ?? "").lowercased()
                let lastName = (profile.last_name ?? "").lowercased()
                let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces).lowercased()
                
                return displayName.contains(searchQuery) ||
                       firstName.contains(searchQuery) ||
                       lastName.contains(searchQuery) ||
                       fullName.contains(searchQuery)
            }
            
            // Convert to UserProfileCard with follow status
            var cards: [UserProfileCard] = []
            for profile in matchingProfiles.prefix(20) {
                let displayName: String
                if let firstName = profile.first_name, let lastName = profile.last_name {
                    displayName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
                } else if let displayNameValue = profile.display_name, !displayNameValue.isEmpty {
                    displayName = displayNameValue
                } else {
                    continue // Skip profiles without names
                }
                
                let handle = displayName.lowercased().replacingOccurrences(of: " ", with: "")
                let initials = generateInitials(firstName: profile.first_name, lastName: profile.last_name, displayName: displayName)
                
                let isFollowing = try? await followService.isFollowing(userId: profile.id)
                
                let user = UserProfileCard(
                    id: profile.id,
                    displayName: displayName,
                    handle: "@\(handle)",
                    avatarInitials: initials,
                    isFollowing: isFollowing ?? false
                )
                
                cards.append(user)
            }
            
            searchResults = cards
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }
    }
    
    private func generateInitials(firstName: String?, lastName: String?, displayName: String) -> String {
        if let firstName = firstName, let lastName = lastName {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            let lastInitial = String(lastName.prefix(1)).uppercased()
            return "\(firstInitial)\(lastInitial)"
        } else {
            return String(displayName.prefix(2)).uppercased()
        }
    }
}

// MARK: - User Profile Card Model

struct UserProfileCard: Identifiable {
    let id: UUID
    let displayName: String
    let handle: String
    let avatarInitials: String
    var isFollowing: Bool
}

// MARK: - User Profile Card View

struct UserProfileCardView: View {
    let user: UserProfileCard
    @State private var isFollowing: Bool
    @State private var isUpdatingFollow = false
    
    private let followService = FollowService.shared
    
    init(user: UserProfileCard) {
        self.user = user
        self._isFollowing = State(initialValue: user.isFollowing)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1DB954"),
                            Color(hex: "#1ED760")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Text(user.avatarInitials)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                )
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(user.handle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Follow Button
            Button {
                Task {
                    await toggleFollow()
                }
            } label: {
                if isUpdatingFollow {
                    ProgressView()
                        .tint(.white)
                        .frame(width: 80, height: 32)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isFollowing ? .white : .black)
                        .frame(width: 80, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isFollowing ? Color.white.opacity(0.2) : Color(hex: "#1ED760"))
                        )
                }
            }
            .disabled(isUpdatingFollow)
        }
        .padding(16)
        .glassMorphism()
    }
    
    private func toggleFollow() async {
        isUpdatingFollow = true
        defer { isUpdatingFollow = false }
        
        do {
            if isFollowing {
                try await followService.unfollow(userId: user.id)
                isFollowing = false
            } else {
                try await followService.follow(userId: user.id)
                isFollowing = true
            }
        } catch {
            print("Failed to toggle follow: \(error)")
        }
    }
}

