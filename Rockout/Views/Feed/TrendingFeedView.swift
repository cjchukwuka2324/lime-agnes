import SwiftUI

struct TrendingFeedView: View {
    @StateObject private var viewModel = TrendingFeedViewModel()
    @State private var selectedPostId: String?
    @State private var showHashtags = false
    
    let initialHashtag: String?
    
    init(initialHashtag: String? = nil) {
        self.initialHashtag = initialHashtag
    }
    
    var body: some View {
        ZStack {
            // Match For You and Following background
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with toggle
                header
                
                if showHashtags {
                    // Hashtags browsing mode
                    if viewModel.selectedHashtag == nil {
                        trendingHashtagsView
                    } else {
                        hashtagPostsView
                    }
                } else {
                    // Trending posts mode (default - matches For You/Following)
                    trendingPostsView
                }
            }
        }
        .task {
            await viewModel.loadTrending()
            await viewModel.loadAllTrendingPosts()
            
            // If an initial hashtag was provided, select it
            if let hashtag = initialHashtag {
                showHashtags = true
                await viewModel.selectHashtagByString(hashtag)
            }
        }
        .onAppear {
            // Start auto-refresh when view appears (every 5 minutes)
            viewModel.startAutoRefresh(interval: 300)
        }
        .onDisappear {
            // Stop auto-refresh when view disappears to save resources
            viewModel.stopAutoRefresh()
        }
        .navigationDestination(item: $selectedPostId) { postId in
            PostDetailView(postId: postId)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                if viewModel.selectedHashtag != nil {
                    // Back button
                    Button {
                        withAnimation {
                            viewModel.selectedHashtag = nil
                            viewModel.hashtagPosts = []
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Trending")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                    }
                }
                
                Spacer()
                
                if let hashtag = viewModel.selectedHashtag {
                    Text(hashtag.displayTag)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                } else {
                    HStack(spacing: 6) {
                        Text("Trending")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("🔥")
                            .font(.title2)
                    }
                }
                
                Spacer()
                
                // Toggle between posts and hashtags
                if viewModel.selectedHashtag == nil {
                    Button {
                        withAnimation {
                            showHashtags.toggle()
                        }
                    } label: {
                        Image(systemName: showHashtags ? "doc.text.fill" : "number.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                
                // Refresh button
                Button {
                    Task {
                        await viewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            Divider()
                .background(Color.white.opacity(0.2))
        }
    }
    
    // MARK: - Trending Posts View (matches For You/Following UI)
    
    private var trendingPostsView: some View {
        ScrollView {
            if viewModel.isLoadingPosts {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 40)
            } else if viewModel.allTrendingPosts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "flame")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No trending posts yet")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Be the first to start trending!")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.allTrendingPosts) { post in
                        FeedCardView(
                            post: post,
                            onLike: { postId in
                                Task {
                                    await viewModel.toggleLike(postId: postId)
                                }
                            },
                            onDelete: { postId in
                                Task {
                                    await viewModel.deletePost(postId: postId)
                                }
                            },
            onHashtagTap: { hashtag in
                showHashtags = true
                Task {
                    await viewModel.selectHashtagByString(hashtag)
                }
            },
                            onTapCard: {
                                selectedPostId = post.id
                            },
                            service: SupabaseFeedService.shared
                        )
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Trending Hashtags View
    
    private var trendingHashtagsView: some View {
        ScrollView {
            if viewModel.isLoadingTrending {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 40)
            } else if viewModel.trendingHashtags.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "number.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No trending hashtags yet")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Be the first to start a trend!")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.trendingHashtags) { hashtag in
                        TrendingHashtagCard(hashtag: hashtag)
                            .onTapGesture {
                                Task {
                                    await viewModel.selectHashtag(hashtag)
                                }
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - Hashtag Posts View
    
    private var hashtagPostsView: some View {
        ScrollView {
            if viewModel.isLoadingPosts {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 40)
            } else if viewModel.hashtagPosts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No posts yet")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.hashtagPosts) { post in
                        FeedCardView(
                            post: post,
                            onLike: { postId in
                                Task {
                                    await viewModel.toggleLike(postId: postId)
                                }
                            },
                            onHashtagTap: { hashtag in
                                Task {
                                    await viewModel.selectHashtagByString(hashtag)
                                }
                            },
                            onTapCard: {
                                selectedPostId = post.id
                            },
                            service: SupabaseFeedService.shared
                        )
                        .onAppear {
                            // Trigger load more when near the end
                            if let lastPost = viewModel.hashtagPosts.last,
                               post.id == lastPost.id,
                               viewModel.hasMorePosts && !viewModel.isLoadingMore {
                                Task {
                                    await viewModel.loadMorePosts()
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
                    if !viewModel.hasMorePosts && !viewModel.hashtagPosts.isEmpty {
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
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
        }
    }
}

// MARK: - Trending Hashtag Card

struct TrendingHashtagCard: View {
    let hashtag: TrendingHashtag
    
    var body: some View {
        HStack(spacing: 16) {
            // Folder Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#1ED760"), Color(hex: "#1DB954")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                VStack(spacing: 2) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                    Text("#")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
            }
            
            // Hashtag Info
            VStack(alignment: .leading, spacing: 4) {
                Text(hashtag.displayTag)
                    .font(.headline.bold())
                    .foregroundColor(.white)
                
                HStack(spacing: 8) {
                    // Post count
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.fill")
                            .font(.caption2)
                        Text("\(hashtag.postCount) posts")
                            .font(.caption)
                    }
                    .foregroundColor(.white.opacity(0.7))
                    
                    Text("•")
                        .foregroundColor(.white.opacity(0.5))
                    
                    // Engagement score (simplified display)
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                        Text("\(Int(hashtag.engagementScore))")
                            .font(.caption)
                    }
                    .foregroundColor(Color(hex: "#1ED760"))
                }
            }
            
            Spacer()
            
            // Folder open indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Helper: Time Ago
    
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m"
        } else if seconds < 86400 {
            return "\(seconds / 3600)h"
        } else {
            return "\(seconds / 86400)d"
        }
    }
}

// MARK: - Preview

#Preview {
    TrendingFeedView()
}

