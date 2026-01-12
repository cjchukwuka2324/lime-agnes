import SwiftUI
import Combine
import Foundation

private struct PostIdWrapper: Identifiable, Hashable {
    let id: String
}

private struct ProfileNavigationWrapper: Identifiable, Hashable {
    let id: UUID
    let initialUser: UserSummary?
    
    init(userId: UUID, initialUser: UserSummary? = nil) {
        self.id = userId
        self.initialUser = initialUser
    }
}

struct FeedView: View {
    @StateObject private var viewModel = FeedViewModel()
    @State private var showComposer = false
    @State private var showUserSearch = false
    @State private var showNotifications = false
    @State private var selectedFeedType: FeedType = .forYou
    @StateObject private var notificationsViewModel = NotificationsViewModel()
    @State private var selectedPostId: PostIdWrapper?
    @State private var selectedProfile: ProfileNavigationWrapper?
    @State private var fabOffset: CGSize = .zero
    @State private var selectedHashtag: String?
    @ObservedObject private var tabBarState = TabBarState.shared
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationBarHidden(true)
                .sheet(isPresented: $showComposer) {
                    PostComposerView { createdPostId in
                        Task {
                            await viewModel.refresh(feedType: selectedFeedType)
                        }
                        // Optionally navigate to created post
                        if let postId = createdPostId {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                selectedPostId = PostIdWrapper(id: postId)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showUserSearch) {
                    UserSearchView()
                }
                .sheet(isPresented: $showNotifications) {
                    NotificationsView()
                }
                .navigationDestination(item: $selectedProfile) { wrapper in
                    UserProfileDetailView(userId: wrapper.id, initialUser: wrapper.initialUser)
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
                .onReceive(NotificationCenter.default.publisher(for: .navigateToPost)) { notification in
                    if let postId = notification.userInfo?["post_id"] as? String {
                        selectedPostId = PostIdWrapper(id: postId)
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
        }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        ZStack {
            // Solid gradient background (no animation)
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
        ZStack(alignment: .top) {
            // Scrollable content that flows from top
            ZStack(alignment: .bottomTrailing) {
                // Show TrendingFeedView for trending tab
                if selectedFeedType == .trending {
                    TrendingFeedView(initialHashtag: selectedHashtag)
                        .onChange(of: selectedFeedType) { _, newValue in
                            // Clear selected hashtag when switching away from trending
                            if newValue != .trending {
                                selectedHashtag = nil
                            }
                        }
                } else {
                    // For You and Following tabs
                    if viewModel.posts.isEmpty {
                        VStack {
                            Spacer()
                            emptyStateView
                            Spacer()
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        postsList
                    }
                }
                
                // Only show compose button for For You and Following
                if selectedFeedType != .trending {
                    floatingActionButton
                }
            }
            .padding(.top, tabBarState.isCollapsed ? 0 : 100) // Adjust padding when collapsed
            
            // Fixed title and toolbar at top - hides on scroll
            VStack(spacing: 0) {
                // Fixed GreenRoom title
                HStack(alignment: .center) {
                    Text("GreenRoom")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.leading, 24)
                    Spacer()
                    // Toolbar buttons with refined spacing
                    HStack(spacing: 20) {
                        notificationsButton
                        searchButton
                    }
                    .padding(.trailing, 24)
                }
                .frame(height: 52)
                .padding(.vertical, 8)
                
                // Feed type picker
                feedTypePicker
            }
            .background(
                // Unified solid background
                Color.black
                    .ignoresSafeArea(edges: .top)
            )
            .offset(y: tabBarState.isCollapsed ? -250 : 0)
            .opacity(tabBarState.isCollapsed ? 0 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabBarState.isCollapsed)
        }
    }
    
    private var postsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    GeometryReader { geometry in
                        let frame = geometry.frame(in: .named("scrollView"))
                        let offset = -frame.minY
                        
                        Color.clear
                            .onChange(of: offset) { oldValue, newValue in
                                print("📊 Offset changed: \(oldValue) → \(newValue)")
                                updateScrollOffset(newValue)
                            }
                    }
                    .frame(height: 0)
                    .id("scrollTop")
                    
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
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .coordinateSpace(name: "scrollView")
            .refreshable {
                await viewModel.refresh(feedType: selectedFeedType)
            }
        }
    }
    
    @State private var lastTriggerOffset: CGFloat?
    // Direction thresholds to trigger hide/show (in points)
    private let hideThreshold: CGFloat = 12
    private let showThreshold: CGFloat = 12
    
    private func updateScrollOffset(_ newOffset: CGFloat) {
        // Initialize on first call
        if lastTriggerOffset == nil {
            lastTriggerOffset = newOffset
            print("🎬 Initial offset: \(newOffset)")
            return
        }
        
        let delta = newOffset - lastTriggerOffset!
        
        // Debug
        print("🔄 Scroll: offset=\(newOffset), deltaFromLastTrigger=\(delta), collapsed=\(tabBarState.isCollapsed)")
        
        // IMPORTANT: offset = -minY, so when scrolling DOWN content, minY becomes negative, offset becomes POSITIVE
        // So: scroll down = delta POSITIVE, scroll up = delta NEGATIVE
        
        // Hide on sufficient downward movement (delta becomes MORE positive)
        if !tabBarState.isCollapsed && delta > hideThreshold {
            print("⬇️ HIDING BARS (delta: \(delta))")
            TabBarState.shared.collapse()
            lastTriggerOffset = newOffset
        }
        // Show on sufficient upward movement (delta becomes MORE negative)
        else if tabBarState.isCollapsed && delta < -showThreshold {
            print("⬆️ SHOWING BARS (delta: \(delta))")
            TabBarState.shared.expand()
            lastTriggerOffset = newOffset
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
            onEcho: { postId in
                Task {
                    await viewModel.toggleEcho(postId: postId)
                }
            },
            onNavigateToParent: { parentPostId in
                selectedPostId = PostIdWrapper(id: parentPostId)
            },
            onTapProfile: { author in
                if let userId = UUID(uuidString: author.id) {
                    // Pre-load with author data for immediate rendering
                    selectedProfile = ProfileNavigationWrapper(userId: userId, initialUser: author)
                }
            },
            onDelete: { postId in
                Task {
                    await viewModel.deletePost(postId: postId)
                }
            },
            onHashtagTap: { hashtag in
                // Switch to Trending tab and filter by hashtag
                selectedHashtag = hashtag
                selectedFeedType = .trending
            },
            onMentionTap: { handle in
                // Search for user by handle and navigate to their profile
                Task {
                    await self.handleMentionTap(handle: handle)
                }
            },
            onTapCard: {
                selectedPostId = PostIdWrapper(id: post.id)
            },
            showInlineReplies: true,
            service: viewModel.service
        )
        .padding(.horizontal, 16)
    }
    
    private var floatingActionButton: some View {
        DraggableFloatingButton(
            offset: $fabOffset,
            action: { showComposer = true }
        )
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            notificationsButton
            searchButton
        }
    }
    
    private var notificationsButton: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                
                // Unread badge
                if notificationsViewModel.unreadCount > 0 {
                    Circle()
                        .fill(Color(hex: "#1ED760"))
                        .frame(width: 8, height: 8)
                        .offset(x: 6, y: -4)
                }
            }
        }
    }
    
    private var searchButton: some View {
        Button {
            showUserSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: selectedFeedType == .following ? "person.2.fill" : "sparkles")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.5))
            
            Text(selectedFeedType == .following ? "No Bars from Followed Users" : GreenRoomBranding.EmptyStates.noBarsYet)
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text(selectedFeedType == .following ? "Follow users to see their Bars here." : "Be the first to drop a Bar! Share your music discoveries or comment on leaderboards.")
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
                        Text("Drop Your First Bar")
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
        Picker("Feed Type", selection: $selectedFeedType) {
            Text("For You").tag(FeedType.forYou)
            Text("Following").tag(FeedType.following)
            Text("Trending 🔥").tag(FeedType.trending)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .onAppear {
            // Customize segmented control appearance with visible capsule
            UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(white: 0.95, alpha: 1.0) // Light grey/white capsule
            UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
            UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.6)], for: .normal)
            UISegmentedControl.appearance().backgroundColor = UIColor(white: 0.2, alpha: 1.0) // Dark background
        }
    }
    
    private func handleMentionTap(handle: String) async {
        // Strip @ if present
        let cleanHandle = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        
        // Search for user by handle
        let social = SupabaseSocialGraphService.shared
        do {
            // Search users by handle
            let (users, _) = try await social.searchUsersPaginated(query: cleanHandle, limit: 10, offset: 0)
            
            // Find exact match by handle
            if let matchedUser = users.first(where: { user in
                let userHandle = user.handle.hasPrefix("@") ? String(user.handle.dropFirst()) : user.handle
                return userHandle.lowercased() == cleanHandle.lowercased()
            }) {
                await MainActor.run {
                    if let userId = UUID(uuidString: matchedUser.id) {
                        selectedProfile = ProfileNavigationWrapper(userId: userId, initialUser: matchedUser)
                    }
                }
            }
        } catch {
            print("Failed to search user by handle: \(error)")
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
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#1ED760"))
                    .clipShape(Capsule())
                    .offset(x: 10, y: -8)
            }
        }
        .frame(width: 30, height: 24)
        .padding(.trailing, 8)
    }
}

// MARK: - Draggable Floating Button

private struct DraggableFloatingButton: View {
    @Binding var offset: CGSize
    let action: () -> Void
    
    @State private var isDragging = false
    @State private var currentDragOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            Button {
                if !isDragging {
                    action()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.2),
                                                Color.white.opacity(0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.5),
                                                Color.white.opacity(0.15)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
                    )
                    .scaleEffect(isDragging ? 1.15 : 1.0)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .offset(
                x: -20 + offset.width + currentDragOffset.width,
                y: -100 + offset.height + currentDragOffset.height
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                        }
                        currentDragOffset = value.translation
                    }
                    .onEnded { value in
                        let screenWidth = geometry.size.width
                        let screenHeight = geometry.size.height
                        
                        // Calculate new offset with boundaries
                        let proposedOffsetX = offset.width + value.translation.width
                        let proposedOffsetY = offset.height + value.translation.height
                        
                        // Default position is -20 from right, -100 from bottom
                        // Allow dragging within reasonable bounds
                        let minX: CGFloat = -screenWidth + 80  // Don't go too far left
                        let maxX: CGFloat = 40                  // Don't go off right edge
                        let minY: CGFloat = -screenHeight + 180 // Don't go too far up
                        let maxY: CGFloat = 40                  // Don't go off bottom
                        
                        let boundedOffsetX = max(minX, min(maxX, proposedOffsetX))
                        let boundedOffsetY = max(minY, min(maxY, proposedOffsetY))
                        
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                            offset = CGSize(width: boundedOffsetX, height: boundedOffsetY)
                            currentDragOffset = .zero
                        }
                        
                        // Delay resetting isDragging to prevent accidental button tap
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            isDragging = false
                        }
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
        }
    }
}
