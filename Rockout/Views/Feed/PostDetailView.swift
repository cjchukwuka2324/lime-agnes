import SwiftUI

struct PostDetailView: View {
    let postId: String
    let service: FeedService
    
    @StateObject private var viewModel: PostDetailViewModel
    @State private var showComposer = false
    
    init(postId: String, service: FeedService = SupabaseFeedService.shared as FeedService) {
        self.postId = postId
        self.service = service
        self._viewModel = StateObject(wrappedValue: PostDetailViewModel(postId: postId, service: service))
    }
    
    var body: some View {
        ZStack {
            // Animated gradient background matching SoundPrint
            AnimatedGradientBackground()
                .ignoresSafeArea()
            
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading thread…")
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
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let rootPost = viewModel.rootPost {
                ScrollView {
                    VStack(spacing: 24) {
                        // Root Post
                        FeedCardView(
                            post: rootPost,
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
                            service: service
                        )
                        
                        // Replies Section
                        if !viewModel.replies.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Replies")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                
                                ForEach(viewModel.topLevelReplies) { reply in
                                    ThreadReplyView(
                                        post: reply,
                                        allReplies: viewModel.replies,
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
                                        service: service,
                                        level: 0
                                    )
                                    .padding(.horizontal, 20)
                                }
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.largeTitle)
                                    .foregroundColor(.white.opacity(0.5))
                                Text("No replies yet")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Be the first to reply!")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .padding(.top, 40)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                        .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            if let rootPost = viewModel.rootPost {
                PostComposerView(
                    service: service,
                    parentPost: rootPost
                ) { createdPostId in
                    Task {
                        await viewModel.refresh()
                    }
                }
            }
        }
        .task {
            if viewModel.rootPost == nil {
                await viewModel.loadThread()
            }
        }
    }
}

// MARK: - Thread Reply View (Nested)

/// A view that displays a reply with nested sub-replies in a thread
struct ThreadReplyView: View {
    let post: Post
    let allReplies: [Post]
    let onLike: ((String) -> Void)?
    let onDelete: ((String) -> Void)?
    let service: FeedService?
    let level: Int
    
    // Max nesting level to prevent infinite recursion
    private let maxLevel = 5
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current reply with indentation
            HStack(spacing: 0) {
                // Indentation based on nesting level
                if level > 0 {
                    ForEach(0..<level, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 2)
                            .padding(.leading, 12)
                    }
                    .padding(.trailing, 8)
                }
                
                FeedCardView(
                    post: post,
                    isReply: true,
                    onLike: onLike,
                    onDelete: onDelete,
                    service: service
                )
            }
            
            // Nested replies (if any and within max level)
            if level < maxLevel {
                let nestedReplies = allReplies.filter { $0.parentPostId == post.id }
                if !nestedReplies.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(nestedReplies) { nestedReply in
                            ThreadReplyView(
                                post: nestedReply,
                                allReplies: allReplies,
                                onLike: onLike,
                                onDelete: onDelete,
                                service: service,
                                level: level + 1
                            )
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}
