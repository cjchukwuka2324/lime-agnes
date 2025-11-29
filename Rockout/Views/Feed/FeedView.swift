import SwiftUI
import Combine

private struct PostIdWrapper: Identifiable, Hashable {
    let id: String
}

private struct ArtistIdWrapper: Identifiable, Hashable {
    let id: String
}

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showComposer = false
    @State private var showUserSearch = false
    @State private var showNotifications = false
    @State private var selectedFeedType: FeedType = .forYou
    @StateObject private var notificationsViewModel = NotificationsViewModel()
    @State private var selectedPostId: PostIdWrapper?
    @State private var selectedArtistId: ArtistIdWrapper?
    @State private var selectedProfileUserId: UUID?
    @State private var showProfile = false
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Feed")
                .navigationBarTitleDisplayMode(.large)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    toolbarContent
                }
                .sheet(isPresented: $showComposer) {
                    PostComposerView {
                        Task {
                            await viewModel.refresh(feedType: selectedFeedType)
                        }
                    }
                }
                .sheet(isPresented: $showUserSearch) {
                    UserSearchView()
                }
                .sheet(isPresented: $showNotifications) {
                    NotificationsView()
                }
                .sheet(isPresented: $showProfile) {
                    if let userId = selectedProfileUserId {
                        NavigationStack {
                            UserProfileDetailView(userId: userId)
                        }
                    }
                }
                .onAppear {
                    if viewModel.posts.isEmpty && !viewModel.isLoading {
                        Task {
                            await viewModel.load(feedType: selectedFeedType)
                        }
                    }
                }
                .onChange(of: selectedFeedType) { _, newType in
                    Task {
                        await viewModel.load(feedType: newType)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .feedDidUpdate)) { _ in
                    Task {
                        await viewModel.load(feedType: selectedFeedType)
                    }
                }
                .task {
                    await notificationsViewModel.refreshUnreadCount()
                }
                .onChange(of: showNotifications) { _, isShowing in
                    if isShowing {
                        Task {
                            await notificationsViewModel.load()
                        }
                    } else {
                        Task {
                            await notificationsViewModel.refreshUnreadCount()
                        }
                    }
                }
                .navigationDestination(item: $selectedPostId) { wrapper in
                    PostDetailView(postId: wrapper.id, service: viewModel.service)
                }
                .navigationDestination(item: $selectedArtistId) { wrapper in
                    RockListView(artistId: wrapper.id)
                }
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        ZStack {
            AnimatedGradientBackground()
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error: error)
            } else {
                feedContent
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
            Text("Loading feed…")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func errorView(error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red.opacity(0.8))
            Text("Oops!")
                .font(.title2.bold())
                .foregroundColor(.white)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                Task {
                    await viewModel.load(feedType: selectedFeedType)
                }
            } label: {
                Text("Try Again")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#1ED760"))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var feedContent: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                feedTypePicker
                
                // Show TrendingFeedView for trending tab
                if selectedFeedType == .trending {
                    TrendingFeedView()
                } else {
                    // For You and Following tabs
                    if viewModel.posts.isEmpty {
                        Spacer()
                        emptyStateView
                        Spacer()
                    } else {
                        postsList
                    }
                }
            }
            
            // Only show compose button for For You and Following
            if selectedFeedType != .trending {
                floatingActionButton
            }
        }
    }
    
    private var postsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.posts) { post in
                    postCardView(for: post)
                        .onAppear {
                            // Trigger load more when near the end
                            if let lastPost = viewModel.posts.last,
                               post.id == lastPost.id,
                               viewModel.hasMorePages && !viewModel.isLoadingMore {
                                Task {
                                    await viewModel.loadMore(feedType: selectedFeedType)
                                }
                            }
                        }
                }
                
                // Loading indicator at bottom
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
                
                // End of feed indicator
                if !viewModel.hasMorePages && !viewModel.posts.isEmpty {
                    HStack {
                        Spacer()
                        Text("You've reached the end")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 16)
            .padding(.bottom, 120)
        }
    }
    
    private func postCardView(for post: Post) -> some View {
        FeedCardView(
            post: post,
            onLike: { postId in
                Task {
                    await viewModel.toggleLike(postId: postId)
                }
            },
            onReply: { parentPost in
                selectedPostId = PostIdWrapper(id: parentPost.id)
            },
            onNavigateToParent: { parentPostId in
                selectedPostId = PostIdWrapper(id: parentPostId)
            },
            onNavigateToRockList: { artistId in
                selectedArtistId = ArtistIdWrapper(id: artistId)
            },
            onTapProfile: {
                if let userId = UUID(uuidString: post.author.id) {
                    selectedProfileUserId = userId
                    showProfile = true
                }
            },
            onDelete: { postId in
                Task {
                    await viewModel.deletePost(postId: postId)
                }
            },
            showInlineReplies: true,
            service: viewModel.service
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            if let parentPostId = post.parentPostId {
                selectedPostId = PostIdWrapper(id: parentPostId)
            } else {
                selectedPostId = PostIdWrapper(id: post.id)
            }
        }
    }
    
    private var floatingActionButton: some View {
        Button {
            showComposer = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#1ED760"),
                                    Color(hex: "#1DB954")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(hex: "#1ED760").opacity(0.4), radius: 12, x: 0, y: 6)
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                )
        }
        .padding(.trailing, 20)
        .padding(.bottom, 100)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            notificationsButton
            searchButton
        }
        
        ToolbarItem(placement: .navigationBarLeading) {
            refreshButton
        }
    }
    
    private var notificationsButton: some View {
        Button {
            showNotifications = true
        } label: {
            NotificationBadgeView(viewModel: notificationsViewModel)
        }
    }
    
    private var searchButton: some View {
        Button {
            showUserSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundColor(.white)
        }
    }
    
    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.load(feedType: selectedFeedType)
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: selectedFeedType == .following ? "person.2.fill" : "sparkles")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.5))
            
            Text(selectedFeedType == .following ? "No Posts from Followed Users" : "No Posts Yet")
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text(selectedFeedType == .following ? "Follow users to see their posts here." : "Be the first to post! Share your music discoveries or comment on leaderboards.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if selectedFeedType == .forYou {
                Button {
                    showComposer = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Create First Post")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "#1ED760"),
                                        Color(hex: "#1DB954")
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .padding(.top, 8)
            }
        }
        .padding()
    }
    
    // MARK: - Feed Type Picker
    
    private var feedTypePicker: some View {
        HStack(spacing: 4) {
            feedTypeButton(title: "For You", type: .forYou)
            feedTypeButton(title: "Following", type: .following)
            feedTypeButton(title: "🔥 Trending", type: .trending)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.15))
        )
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    private func feedTypeButton(title: String, type: FeedType) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedFeedType = type
            }
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(selectedFeedType == type ? .white : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Group {
                        if selectedFeedType == type {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(hex: "#1ED760"),
                                            Color(hex: "#1DB954")
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: Color(hex: "#1ED760").opacity(0.3), radius: 8, x: 0, y: 2)
                        }
                    }
                )
        }
    }
}

// MARK: - Helper Views

private struct NotificationBadgeView: View {
    @ObservedObject var viewModel: NotificationsViewModel
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell")
                .font(.title3)
                .foregroundColor(.white)
            
            let unreadCount = viewModel.unreadCount
            if unreadCount > 0 {
                Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color(hex: "#1ED760"))
                    .clipShape(Circle())
                    .offset(x: 6, y: -6)
            }
        }
    }
}
