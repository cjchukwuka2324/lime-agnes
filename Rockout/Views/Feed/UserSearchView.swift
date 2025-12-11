import SwiftUI
import Supabase
import Combine

struct UserSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [UserProfileCard] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasMorePages = true
    @State private var errorMessage: String?
    @State private var selectedUserId: UUID?
    @State private var currentOffset = 0
    
    private let profileService = UserProfileService.shared
    private let followService = FollowService.shared
    private let supabase = SupabaseService.shared.client
    private let social = SupabaseSocialGraphService.shared
    private let pageSize = 20
    private let contactService = SystemContactsService()
    private let contactSyncService: ContactSyncService = SupabaseContactSyncService.shared
    
    // Debounce publisher
    @State private var searchTask: Task<Void, Never>?
    
    // Contact suggestions
    @State private var contactSuggestions: [MatchedContact] = []
    @State private var isLoadingContacts = false
    @State private var hasSyncedContacts = false
    
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
                        
                        TextField("Search by name, @handle, or email...", text: $searchText)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
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
                    } else if searchResults.isEmpty && searchText.isEmpty {
                        // Show contact suggestions when search is empty
                        if isLoadingContacts {
                            Spacer()
                            ProgressView()
                                .tint(.white)
                            Text("Loading suggestions...")
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.top)
                            Spacer()
                        } else if !contactSuggestions.isEmpty {
                            ScrollView {
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
                                .padding(.vertical, 20)
                            }
                        } else {
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
                                
                                Button {
                                    Task {
                                        await syncContactsAndLoadSuggestions()
                                    }
                                } label: {
                                    Text("Find Friends from Contacts")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                        .background(Color(hex: "#1ED760"))
                                        .cornerRadius(20)
                                }
                                .padding(.top, 8)
                            }
                            .padding()
                            Spacer()
                        }
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        Spacer()
                        Text("No users found")
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(searchResults.indices, id: \.self) { index in
                                    NavigationLink {
                                        UserProfileDetailView(userId: searchResults[index].id)
                                    } label: {
                                        UserProfileCardView(
                                            user: searchResults[index],
                                            onFollowChanged: { isFollowing in
                                                // Update the search result when follow status changes
                                                searchResults[index].isFollowing = isFollowing
                                            }
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.horizontal, 20)
                                    .onAppear {
                                        // Load more when we reach the last item
                                        if index == searchResults.count - 1 && hasMorePages && !isLoadingMore {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                // Load contact suggestions on appear if not already loaded
                if !hasSyncedContacts {
                    await syncContactsAndLoadSuggestions()
                }
            }
        }
    }
    
    private func syncContactsAndLoadSuggestions() async {
        isLoadingContacts = true
        defer { isLoadingContacts = false }
        
        do {
            // Request permission and fetch contacts
            guard await contactService.requestPermission() else {
                return
            }
            
            let contacts = try await contactService.fetchContacts()
            
            // Sync contacts to server and get matches
            let matchedContacts = try await contactSyncService.syncContacts(contacts)
            
            // Filter to only show contacts with accounts (for suggestions)
            // Contacts without accounts will be shown with invite option
            contactSuggestions = matchedContacts
            hasSyncedContacts = true
        } catch {
            print("Failed to sync contacts: \(error)")
        }
    }
    
    private func inviteContact(_ contact: MatchedContact) {
        // Open Messages app with pre-filled invite message
        let inviteMessage = "Join me on RockOut! Download the app: [App Store Link]"
        
        // Create SMS URL
        if let phone = contact.contactPhone {
            let phoneNumber = phone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            let smsURLString = "sms:\(phoneNumber)&body=\(inviteMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
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
            
            // Convert UserSummary to UserProfileCard
            let cards = result.users.map { userSummary in
                UserProfileCard(
                    id: UUID(uuidString: userSummary.id) ?? UUID(),
                    displayName: userSummary.displayName,
                    handle: userSummary.handle,
                    avatarInitials: userSummary.avatarInitials,
                    isFollowing: userSummary.isFollowing
                )
            }
            
            if resetPagination {
                searchResults = cards
            } else {
                searchResults.append(contentsOf: cards)
            }
            
            currentOffset += pageSize
            hasMorePages = result.hasMore
            
        } catch {
            errorMessage = error.localizedDescription
            if resetPagination {
                searchResults = []
            }
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

struct UserProfileCard: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let handle: String
    let avatarInitials: String
    var isFollowing: Bool
    
    static func == (lhs: UserProfileCard, rhs: UserProfileCard) -> Bool {
        return lhs.id == rhs.id
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
        .onAppear {
            // Sync internal state with user object when view appears
            isFollowing = user.isFollowing
        }
        .onChange(of: user.isFollowing) { _, newValue in
            // Update internal state when user object changes
            isFollowing = newValue
        }
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

