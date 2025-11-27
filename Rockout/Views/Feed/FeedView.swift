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
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading feed…")
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else if let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            Task {
                                await viewModel.load(feedType: selectedFeedType)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    ZStack(alignment: .bottomTrailing) {
                        VStack(spacing: 0) {
                            // Feed Type Picker
                            feedTypePicker
                            
                            if viewModel.posts.isEmpty {
                                Spacer()
                                VStack(spacing: 16) {
                                    Image(systemName: selectedFeedType == .following ? "person.2" : "sparkles")
                                        .font(.largeTitle)
                                        .foregroundColor(.white.opacity(0.6))
                                    Text(selectedFeedType == .following ? "No Posts from Followed Users" : "No Posts Yet")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text(selectedFeedType == .following ? "Follow users to see their posts here." : "Be the first to post! Share your music discoveries or comment on leaderboards.")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                .padding()
                                Spacer()
                            } else {
                                ScrollView {
                                    VStack(spacing: 20) {
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
                                            .padding(.horizontal, 20)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                // Navigate to post detail when tapping the card
                                                selectedPostId = PostIdWrapper(id: post.id)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 20)
                                    .padding(.bottom, 100) // Add padding to prevent overlap with FAB
                                }
                            }
                        }
                        
                        // Floating Action Button
                        Button {
                            showComposer = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
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
                                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                                )
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 100) // Position above tab bar
                    }
                }
            }
            .navigationTitle("Feed")
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
    
    // MARK: - Feed Type Picker
    
    private var feedTypePicker: some View {
        HStack(spacing: 0) {
            Button {
                selectedFeedType = .forYou
            } label: {
                Text("For You")
                    .font(.headline)
                    .foregroundColor(selectedFeedType == .forYou ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 0)
                            .fill(selectedFeedType == .forYou ? Color.white.opacity(0.2) : Color.clear)
                    )
            }
            
            Button {
                selectedFeedType = .following
            } label: {
                Text("Following")
                    .font(.headline)
                    .foregroundColor(selectedFeedType == .following ? .white : .white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 0)
                            .fill(selectedFeedType == .following ? Color.white.opacity(0.2) : Color.clear)
                    )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}