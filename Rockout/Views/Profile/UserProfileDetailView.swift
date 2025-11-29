import SwiftUI

struct UserProfileDetailView: View {
    let userId: UUID
    
    @StateObject private var viewModel: UserProfileViewModel
    
    @State private var showFollowersList = false
    @State private var showFollowingList = false
    @State private var showMutualsList = false
    
    init(userId: UUID) {
        self.userId = userId
        self._viewModel = StateObject(wrappedValue: UserProfileViewModel(userId: userId.uuidString))
    }
    
    private var isCurrentUser: Bool {
        guard let currentUserId = SupabaseService.shared.client.auth.currentUser?.id.uuidString else {
            return false
        }
        return currentUserId == userId.uuidString
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated gradient background matching SoundPrint
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Header with Picture
                        profileHeaderSection
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // Content Tabs (Posts, Replies, Likes)
                        profileContentTabs
                            .padding(.horizontal, 20)
                        
                        Spacer()
                            .frame(height: 20)
                    }
                }
            }
            .navigationTitle(profileDisplayName)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await viewModel.load()
            }
        }
    }
    
    // MARK: - Profile Header Section
    
    private var profileHeaderSection: some View {
        VStack(spacing: 20) {
            // Profile Picture
            Group {
                if let imageURL = profilePictureURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            defaultProfileAvatar
                        @unknown default:
                            defaultProfileAvatar
                        }
                    }
                } else {
                    defaultProfileAvatar
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
            
            // User Name
            Text(profileDisplayName)
                .font(.title2.bold())
                .foregroundColor(.white)
            
            if let handle = profileHandle {
                Text(handle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Follow Button and Post Notifications Toggle (only show if not current user)
            if !isCurrentUser {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.toggleFollow()
                        }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 120, height: 40)
                        } else {
                            Text(viewModel.user?.isFollowing ?? false ? "Following" : "Follow")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(viewModel.user?.isFollowing ?? false ? .white : .black)
                                .frame(width: 120, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(viewModel.user?.isFollowing ?? false ? Color.white.opacity(0.2) : Color(hex: "#1ED760"))
                                )
                        }
                    }
                    .disabled(viewModel.isLoading)
                    
                    // Post Notifications Toggle (only show if following)
                    if viewModel.user?.isFollowing == true {
                        Button {
                            Task {
                                await viewModel.togglePostNotifications()
                            }
                        } label: {
                            Image(systemName: viewModel.isPostNotificationsOn ? "bell.fill" : "bell.slash.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                    }
                }
            }
            
            // Stats
            HStack(spacing: 32) {
                Button {
                    showFollowersList = true
                } label: {
                    VStack {
                        Text("\(viewModel.followerCount)")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Text("Followers")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Button {
                    showFollowingList = true
                } label: {
                    VStack {
                        Text("\(viewModel.followingCount)")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Text("Following")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .sheet(isPresented: $showFollowersList) {
                FollowersFollowingListView(userId: userId.uuidString, mode: .followers)
            }
            .sheet(isPresented: $showFollowingList) {
                FollowersFollowingListView(userId: userId.uuidString, mode: .following)
            }
            .sheet(isPresented: $showMutualsList) {
                FollowersFollowingListView(userId: userId.uuidString, mode: .mutuals)
            }
        }
    }
    
    private var defaultProfileAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.2),
                        Color.white.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(profileInitials)
                    .font(.title.bold())
                    .foregroundColor(.white)
            )
    }
    
    private var profileDisplayName: String {
        viewModel.user?.displayName ?? "User"
    }
    
    private var profileHandle: String? {
        viewModel.user?.handle
    }
    
    private var profileInitials: String {
        viewModel.user?.avatarInitials ?? "U"
    }
    
    private var profilePictureURL: URL? {
        viewModel.user?.profilePictureURL
    }
    
    // MARK: - Profile Content Tabs
    
    private var profileContentTabs: some View {
        VStack(spacing: 20) {
            // Tab Picker
            Picker("Content Type", selection: Binding(
                get: {
                    switch viewModel.selectedSection {
                    case .posts: return ProfileContentTab.posts
                    case .replies: return ProfileContentTab.replies
                    case .likes: return ProfileContentTab.likes
                    case .followers: return ProfileContentTab.followers
                    case .following: return ProfileContentTab.following
                    case .mutuals: return ProfileContentTab.mutuals
                    }
                },
                set: { (newTab: ProfileContentTab) in
                    switch newTab {
                    case .posts: viewModel.selectedSection = .posts
                    case .replies: viewModel.selectedSection = .replies
                    case .likes: viewModel.selectedSection = .likes
                    case .followers: viewModel.selectedSection = .followers
                    case .following: viewModel.selectedSection = .following
                    case .mutuals: viewModel.selectedSection = .mutuals
                    }
                }
            )) {
                Text("Posts").tag(ProfileContentTab.posts)
                Text("Likes").tag(ProfileContentTab.likes)
                Text("Followers").tag(ProfileContentTab.followers)
                Text("Following").tag(ProfileContentTab.following)
                Text("Mutuals").tag(ProfileContentTab.mutuals)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Content View
            Group {
                switch viewModel.selectedSection {
                case .posts:
                    postsContentList
                case .replies:
                    postsContentList // For now, use same as posts
                case .likes:
                    likesContentList
                case .followers:
                    userListContent(users: viewModel.followers, emptyIcon: "person.2", emptyTitle: "No followers yet", emptyMessage: "When someone follows this user, they'll appear here")
                case .following:
                    userListContent(users: viewModel.following, emptyIcon: "person.2.fill", emptyTitle: "Not following anyone", emptyMessage: "This user isn't following anyone yet")
                case .mutuals:
                    userListContent(users: viewModel.mutuals, emptyIcon: "person.3", emptyTitle: "No mutual follows", emptyMessage: "Users you both follow will appear here")
                }
            }
        }
    }
    
    @ViewBuilder
    private var postsContentList: some View {
        if viewModel.posts.isEmpty {
            emptyStateView(icon: "square.and.pencil", title: "No posts yet", message: "This user hasn't shared any posts yet.")
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.posts) { post in
                        FeedCardView(post: post)
                    }
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    private var likesContentList: some View {
        if viewModel.likedPosts.isEmpty {
            emptyStateView(icon: "heart", title: "No likes yet", message: "This user hasn't liked any posts yet.")
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.likedPosts) { post in
                        FeedCardView(post: post)
                    }
                }
                .padding()
            }
        }
    }
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.white.opacity(0.5))
            Text(title)
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            Text(message)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    enum ProfileContentTab: String, CaseIterable {
        case posts = "Posts"
        case replies = "Replies"
        case likes = "Likes"
        case followers = "Followers"
        case following = "Following"
        case mutuals = "Mutuals"
    }
    
    @ViewBuilder
    private func userListContent(users: [UserSummary], emptyIcon: String, emptyTitle: String, emptyMessage: String) -> some View {
        if users.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: emptyIcon)
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.5))
                Text(emptyTitle)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(users) { user in
                        NavigationLink {
                            UserProfileDetailView(userId: UUID(uuidString: user.id) ?? UUID())
                        } label: {
                            UserCardView(user: user)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
        }
    }
    
    @ViewBuilder
    private func profileContentList(viewModel: FeedViewModel, emptyIcon: String, emptyTitle: String, emptyMessage: String) -> some View {
        if viewModel.isLoading {
            HStack {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            }
            .padding()
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if viewModel.posts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: emptyIcon)
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.5))
                Text(emptyTitle)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.posts) { post in
                    FeedCardView(
                        post: post,
                        showInlineReplies: true,
                        service: SupabaseFeedService.shared
                    )
                }
            }
        }
    }
    
}
