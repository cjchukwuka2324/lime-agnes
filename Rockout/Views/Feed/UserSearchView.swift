import SwiftUI
import Supabase
import Combine
import Foundation

enum UserFilter: String, CaseIterable {
    case all = "All"
    case following = "Following"
    case notFollowing = "Not Following"
}

enum SortOption: String, CaseIterable {
    case relevance = "Relevance"
    case name = "Name"
    case newest = "Newest"
}

struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    @State private var searchResults: [UserProfileCard] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    @State private var errorMessage: String?
    @State private var selectedUserId: UUID?
    @State private var currentOffset = 0
    @State private var selectedFilter: UserFilter = .all
    @State private var sortOption: SortOption = .relevance
    @AppStorage("recentSearches") private var recentSearchesData: Data = Data()
    
    private let profileService = UserProfileService.shared
    private let followService = FollowService.shared
    private let supabase = SupabaseService.shared.client
    private let social = SupabaseSocialGraphService.shared
    private let pageSize = 20
    private let contactService = SystemContactsService()
    private let contactSyncService: ContactSyncService = SupabaseContactSyncService.shared
    private let suggestedFollowService: SuggestedFollowService = SupabaseSuggestedFollowService()
    
    // Debounce publisher
    @State private var searchTask: Task<Void, Never>?
    
    // Contact suggestions
    @State private var contactSuggestions: [MatchedContact] = []
    @State private var isLoadingContacts = false
    @State private var hasSyncedContacts = false
    
    // Mutual follow suggestions
    @State private var mutualSuggestions: [MutualFollowSuggestion] = []
    @State private var isLoadingMutuals = false
    
    // Recent searches helper functions
    private func getRecentSearches() -> [UserProfileCard] {
        guard let decoded = try? JSONDecoder().decode([UserProfileCard].self, from: recentSearchesData) else {
            return []
        }
        return Array(decoded.prefix(15)) // Keep last 15 profiles
    }
    
    private func setRecentSearches(_ searches: [UserProfileCard]) {
        if let encoded = try? JSONEncoder().encode(Array(searches.prefix(15))) {
            recentSearchesData = encoded
        }
    }
    
    private var filteredAndSortedResults: [UserProfileCard] {
        var results = searchResults
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .following:
            results = results.filter { $0.isFollowing }
        case .notFollowing:
            results = results.filter { !$0.isFollowing }
        }
        
        // Apply sorting
        switch sortOption {
        case .relevance:
            // Already sorted by relevance from search
            break
        case .name:
            results = results.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .newest:
            // Not applicable without timestamps, keep as is
            break
        }
        
        return results
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Solid black background
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.6))
                        
                        TextField("Search by name, @handle, or email...", text: $searchText)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isSearchFocused)
                            .onChange(of: searchText) { _, newValue in
                                // Cancel previous search task
                                searchTask?.cancel()
                                
                                if newValue.isEmpty {
                                    searchResults = []
                                    currentOffset = 0
                                    hasMorePages = true
                                } else {
                                    // Debounce search by 500ms
                                    searchTask = Task {
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        if !Task.isCancelled {
                                            await searchUsers(query: newValue, resetPagination: true)
                                        }
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
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
                    } else if filteredAndSortedResults.isEmpty && !searchText.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.6))
                            Text("No users found")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(selectedFilter != .all ? "Try changing the filter" : "Try a different search term")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        Spacer()
                    } else if searchResults.isEmpty && searchText.isEmpty {
                        // Show recent searches, mutual and contact suggestions when search is empty
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                // Recent Searches
                                if !getRecentSearches().isEmpty {
                                    VStack(alignment: .leading, spacing: 16) {
                                        HStack {
                                            Text("Recent Searches")
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            Spacer()
                                            Button("Clear") {
                                                setRecentSearches([])
                                            }
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.7))
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.top, 20)
                                        
                                        ForEach(getRecentSearches()) { recentProfile in
                                            NavigationLink {
                                                UserProfileDetailView(userId: recentProfile.id)
                                            } label: {
                                                UserProfileCardView(
                                                    user: recentProfile,
                                                    onFollowChanged: { isFollowing in
                                                        // Update the profile in recent searches
                                                        var searches = getRecentSearches()
                                                        if let index = searches.firstIndex(where: { $0.id == recentProfile.id }) {
                                                            searches[index].isFollowing = isFollowing
                                                            setRecentSearches(searches)
                                                        }
                                                    }
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .padding(.horizontal, 20)
                                        }
                                    }
                                }
                                
                                // Mutual Follow Suggestions
                                if !mutualSuggestions.isEmpty {
                                    VStack(alignment: .leading, spacing: 16) {
                                        HStack {
                                            Text("Suggested for You")
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.top, 20)
                                        
                                        ForEach(mutualSuggestions) { suggestion in
                                            NavigationLink {
                                                UserProfileDetailView(
                                                    userId: UUID(uuidString: suggestion.user.id) ?? UUID(),
                                                    initialUser: suggestion.user
                                                )
                                            } label: {
                                                MutualFollowSuggestionCard(
                                                    suggestion: suggestion,
                                                    onFollowChanged: { _ in
                                                        // Refresh suggestions after follow change
                                                        Task {
                                                            await loadMutualSuggestions()
                                                        }
                                                    }
                                                )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .padding(.horizontal, 20)
                                        }
                                    }
                                }
                                
                                // Contact Suggestions
                                if isLoadingContacts {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .tint(.white)
                                        Spacer()
                                    }
                                    .padding()
                                } else if !contactSuggestions.isEmpty {
                                    VStack(alignment: .leading, spacing: 16) {
                                        HStack {
                                            Text("Suggested from Contacts")
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.top, 20)
                                        
                                        ForEach(Array(contactSuggestions), id: \.id) { contact in
                                            if let matchedUser = contact.matchedUser {
                                                // User has account - show as follow suggestion
                                                NavigationLink {
                                                    UserProfileDetailView(userId: UUID(uuidString: matchedUser.id) ?? UUID(), initialUser: matchedUser)
                                                } label: {
                                                    ContactSuggestionCard(
                                                        contact: contact,
                                                        isInvite: false,
                                                        onFollowChanged: { _ in }
                                                    )
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                .padding(.horizontal, 20)
                                            } else {
                                                // User doesn't have account - show invite option
                                                ContactSuggestionCard(
                                                    contact: contact,
                                                    isInvite: true,
                                                    onFollowChanged: nil,
                                                    onInvite: {
                                                        inviteContact(contact)
                                                    }
                                                )
                                                .padding(.horizontal, 20)
                                            }
                                        }
                                    }
                                } else if mutualSuggestions.isEmpty && contactSuggestions.isEmpty && !isLoadingContacts && !isLoadingMutuals {
                                    // Empty state - recent searches will show above if available
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 20)
                        }
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        Spacer()
                        Text("No users found")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                    } else {
                        let filtered = filteredAndSortedResults
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                        ForEach(filtered.indices, id: \.self) { index in
                                    NavigationLink {
                                        UserProfileDetailView(userId: filtered[index].id)
                                    } label: {
                                        UserProfileCardView(
                                            user: filtered[index],
                                            onFollowChanged: { isFollowing in
                                                // Update the search result when follow status changes
                                                if let originalIndex = searchResults.firstIndex(where: { $0.id == filtered[index].id }) {
                                                    searchResults[originalIndex].isFollowing = isFollowing
                                                }
                                                // Also update in recent searches if it exists there
                                                var recent = getRecentSearches()
                                                if let recentIndex = recent.firstIndex(where: { $0.id == filtered[index].id }) {
                                                    recent[recentIndex].isFollowing = isFollowing
                                                    setRecentSearches(recent)
                                                }
                                            }
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.horizontal, 20)
                                    .onAppear {
                                        // Load more when we reach the last item (based on original results, not filtered)
                                        if index == filtered.count - 1 && hasMorePages && !isLoadingMore {
                                            Task {
                                                await searchUsers(query: searchText, resetPagination: false)
                                            }
                                        }
                                    }
                                }
                                
                                // Loading more indicator
                                if isLoadingMore {
                                    ProgressView()
                                        .tint(.white)
                                        .padding()
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !searchResults.isEmpty {
                        Menu {
                            // Filter options
                            Menu {
                                ForEach(UserFilter.allCases, id: \.self) { filter in
                                    Button {
                                        selectedFilter = filter
                                    } label: {
                                        HStack {
                                            Text(filter.rawValue)
                                            if selectedFilter == filter {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                            }
                            
                            // Sort options
                            Menu {
                                ForEach(SortOption.allCases, id: \.self) { sort in
                                    Button {
                                        sortOption = sort
                                    } label: {
                                        HStack {
                                            Text(sort.rawValue)
                                            if sortOption == sort {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Label("Sort", systemImage: "arrow.up.arrow.down")
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.white)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                // Load mutual and contact suggestions on appear
                await loadMutualSuggestions()
                if !hasSyncedContacts {
                    await syncContactsAndLoadSuggestions()
                }
            }
        }
    }
    
    private func loadMutualSuggestions() async {
        isLoadingMutuals = true
        defer { isLoadingMutuals = false }
        
        do {
            let suggestions = try await suggestedFollowService.getMutualFollowSuggestions(limit: 10)
            await MainActor.run {
                mutualSuggestions = suggestions
                print("✅ Loaded \(suggestions.count) mutual follow suggestions")
            }
        } catch {
            print("❌ Failed to load mutual suggestions: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ Error userInfo: \(nsError.userInfo)")
            }
            await MainActor.run {
                mutualSuggestions = []
            }
        }
    }
    
    private func syncContactsAndLoadSuggestions() async {
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        
        do {
            // Request permission and fetch contacts
            guard await contactService.requestPermission() else {
                print("⚠️ Contact permission not granted")
                return
            }
            
            print("✅ Contact permission granted, fetching contacts...")
            let contacts = try await contactService.fetchContacts()
            print("✅ Fetched \(contacts.count) contacts")
            
            // Sync contacts to server and get matches
            print("🔄 Syncing contacts to server...")
            let matchedContacts = try await contactSyncService.syncContacts(contacts)
            print("✅ Synced contacts, got \(matchedContacts.count) matched contacts")
            
            // Get matched contacts from server
            let serverMatchedContacts = try await contactSyncService.getMatchedContacts()
            print("✅ Retrieved \(serverMatchedContacts.count) matched contacts from server")
            
            // Filter to only show contacts with accounts (for suggestions)
            // Contacts without accounts will be shown with invite option
            await MainActor.run {
                contactSuggestions = serverMatchedContacts
                hasSyncedContacts = true
                print("✅ Updated contactSuggestions with \(serverMatchedContacts.count) contacts")
            }
        } catch {
            print("❌ Failed to sync contacts: \(error)")
            await MainActor.run {
                contactSuggestions = []
            }
        }
    }
    
    private func inviteContact(_ contact: MatchedContact) {
        // Generate invite message with proper sign-up link
        let inviteMessage = InviteLinkGenerator.generateInviteMessage()
        
        // Create SMS URL
        if let phone = contact.contactPhone {
            let phoneNumber = phone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            let smsURLString = "sms:\(phoneNumber)&body=\(inviteMessage.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? "")"
            if let url = URL(string: smsURLString) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
    
    private func searchUsers(query: String, resetPagination: Bool) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        
        if resetPagination {
            isLoading = true
            currentOffset = 0
            hasMorePages = true
        } else {
            isLoadingMore = true
        }
        
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }
        
        do {
            // Use the paginated RPC function
            let result = try await social.searchUsersPaginated(
                query: query,
                limit: pageSize,
                offset: currentOffset
            )
            
            // Check if task was cancelled before updating UI
            guard !Task.isCancelled else { return }
            
            // Convert UserSummary to UserProfileCard
            let cards = result.users.map { userSummary in
                UserProfileCard(
                    id: UUID(uuidString: userSummary.id) ?? UUID(),
                    displayName: userSummary.displayName,
                    handle: userSummary.handle,
                    avatarInitials: userSummary.avatarInitials,
                    profilePictureURLString: userSummary.profilePictureURL?.absoluteString,
                    isFollowing: userSummary.isFollowing
                )
            }
            
            if resetPagination {
                searchResults = cards
                // Save profiles to recent searches
                addProfilesToRecentSearches(cards)
            } else {
                searchResults.append(contentsOf: cards)
            }
            
            currentOffset += pageSize
            hasMorePages = result.hasMore
            
        } catch {
            // Only show error if task wasn't cancelled
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            if resetPagination {
                searchResults = []
            }
        }
    }
    
    private func addProfilesToRecentSearches(_ profiles: [UserProfileCard]) {
        guard !profiles.isEmpty else { return }
        
        var recent = getRecentSearches()
        var recentIds = Set(recent.map { $0.id })
        
        // Add new profiles, avoiding duplicates by ID
        for profile in profiles {
            if recentIds.contains(profile.id) {
                // Update existing profile and move to front
                if let index = recent.firstIndex(where: { $0.id == profile.id }) {
                    recent.remove(at: index)
                    recent.insert(profile, at: 0)
                }
            } else {
                // Add new profile at the beginning
                recent.insert(profile, at: 0)
                recentIds.insert(profile.id) // Track added IDs to prevent duplicates within batch
            }
        }
        
        setRecentSearches(recent)
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

struct UserProfileCard: Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var handle: String
    var avatarInitials: String
    var profilePictureURLString: String?
    var isFollowing: Bool
    
    var profilePictureURL: URL? {
        guard let urlString = profilePictureURLString else { return nil }
        return URL(string: urlString)
    }
    
    static func == (lhs: UserProfileCard, rhs: UserProfileCard) -> Bool {
        return lhs.id == rhs.id
    }
}

extension UserProfileCard: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case handle
        case avatarInitials
        case profilePictureURLString
        case profilePictureURL  // Support old field name for backward compatibility (stored as String in JSON)
        case isFollowing
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        handle = try container.decode(String.self, forKey: .handle)
        avatarInitials = try container.decode(String.self, forKey: .avatarInitials)
        isFollowing = try container.decode(Bool.self, forKey: .isFollowing)
        
        // Try new field name first, then fall back to old field name for backward compatibility
        // Note: In JSON, URLs are always strings, so we decode both as String
        if let urlString = try container.decodeIfPresent(String.self, forKey: .profilePictureURLString) {
            profilePictureURLString = urlString
        } else if let urlString = try container.decodeIfPresent(String.self, forKey: .profilePictureURL) {
            profilePictureURLString = urlString
        } else {
            profilePictureURLString = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(handle, forKey: .handle)
        try container.encode(avatarInitials, forKey: .avatarInitials)
        try container.encode(isFollowing, forKey: .isFollowing)
        try container.encodeIfPresent(profilePictureURLString, forKey: .profilePictureURLString)
    }
}

// MARK: - User Profile Card View

struct UserProfileCardView: View {
    let user: UserProfileCard
    let onFollowChanged: ((Bool) -> Void)?
    @State private var isFollowing: Bool
    @State private var isUpdatingFollow = false
    
    private let followService = FollowService.shared
    
    init(user: UserProfileCard, onFollowChanged: ((Bool) -> Void)? = nil) {
        self.user = user
        self.onFollowChanged = onFollowChanged
        self._isFollowing = State(initialValue: user.isFollowing)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let pictureURL = user.profilePictureURL {
                    AsyncImage(url: pictureURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white.opacity(0.6))
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            avatarFallback
                        @unknown default:
                            avatarFallback
                        }
                    }
                } else {
                    avatarFallback
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            
            // User Info
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(user.handle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
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
        .padding(12)
        .glassMorphism()
        .onAppear {
            // Sync internal state with user object when view appears
            isFollowing = user.isFollowing
        }
        .onChange(of: user.isFollowing) { _, newValue in
            // Update internal state when user object changes
            isFollowing = newValue
        }
    }
    
    private var avatarFallback: some View {
        ZStack {
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
            
            Text(user.avatarInitials)
                .font(.title3.bold())
                .foregroundColor(.white)
        }
        .frame(width: 48, height: 48)
    }
    
    private func toggleFollow() async {
        isUpdatingFollow = true
        defer { isUpdatingFollow = false }
        
        do {
            if isFollowing {
                try await followService.unfollow(userId: user.id)
                isFollowing = false
                onFollowChanged?(false)
            } else {
                try await followService.follow(userId: user.id)
                isFollowing = true
                onFollowChanged?(true)
            }
        } catch {
            print("Failed to toggle follow: \(error)")
        }
    }
}

