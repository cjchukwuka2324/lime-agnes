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
    @State private var unreadNotificationCount = 0
    @State private var selectedPostId: PostIdWrapper?
    @State private var selectedArtistId: ArtistIdWrapper?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated gradient background matching SoundPrint
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                        Text("Loading feed…")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.errorMessage {
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
                } else {
                    ZStack(alignment: .bottomTrailing) {
                        VStack(spacing: 0) {
                            // Feed Type Picker
                            feedTypePicker
                            
                            if viewModel.posts.isEmpty {
                                Spacer()
                                emptyStateView
                                Spacer()
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 16) {
                                        ForEach(viewModel.posts) { post in
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
                                                showInlineReplies: true,
                                                service: viewModel.service
                                            )
                                            .padding(.horizontal, 16)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedPostId = PostIdWrapper(id: post.id)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 16)
                                    .padding(.bottom, 120)
                                }
                                .refreshable {
                                    await viewModel.load(feedType: selectedFeedType)
                                }
                            }
                        }
                        
                        // Floating Action Button
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
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showNotifications = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.title3)
                                .foregroundColor(.white)
                            
                            if unreadNotificationCount > 0 {
                                Text("\(unreadNotificationCount > 99 ? "99+" : "\(unreadNotificationCount)")")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color(hex: "#1ED760"))
                                    .clipShape(Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                    }
                    
                    Button {
                        showUserSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task {
                            await viewModel.load(feedType: selectedFeedType)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                    }
                }
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
                // Automatically refresh feed when a new post is created
                Task {
                    await viewModel.load(feedType: selectedFeedType)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .notificationReceived)) { _ in
                // Update notification count when new notification is received
                Task {
                    unreadNotificationCount = await NotificationService.shared.getUnreadCount()
                }
            }
            .task {
                // Load initial notification count
                unreadNotificationCount = await NotificationService.shared.getUnreadCount()
            }
            .navigationDestination(item: $selectedPostId) { wrapper in
                PostDetailView(postId: wrapper.id, service: viewModel.service)
            }
            .navigationDestination(item: $selectedArtistId) { wrapper in
                RockListView(artistId: wrapper.id)
            }
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
        HStack(spacing: 8) {
            feedTypeButton(title: "For You", type: .forYou)
            feedTypeButton(title: "Following", type: .following)
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