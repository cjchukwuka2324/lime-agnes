import SwiftUI

struct PostDetailView: View {
    let postId: String
    let service: FeedService
    
    @StateObject private var viewModel: PostDetailViewModel
    @State private var showComposer = false
    @State private var selectedProfile: ProfileNavigationWrapper?
    
    init(postId: String, service: FeedService = SupabaseFeedService.shared as FeedService) {
        self.postId = postId
        self.service = service
        self._viewModel = StateObject(wrappedValue: PostDetailViewModel(postId: postId, service: service))
    }
    
    var body: some View {
        ZStack {
            // Solid black background
            Color.black.ignoresSafeArea()
            
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
                            onReply: { parentPost in
                                showComposer = true
                            },
                            onTapProfile: { author in
                                if let userId = UUID(uuidString: author.id) {
                                    selectedProfile = ProfileNavigationWrapper(userId: userId, initialUser: author)
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
                                Text(GreenRoomBranding.SectionHeadings.adlibs)
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
                                        onTapProfile: { author in
                                            if let userId = UUID(uuidString: author.id) {
                                                selectedProfile = ProfileNavigationWrapper(userId: userId, initialUser: author)
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
                                Text(GreenRoomBranding.EmptyStates.noAdlibsYet)
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.7))
                                Text(GreenRoomBranding.EmptyStates.beFirstToAdlib)
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
        .navigationTitle(GreenRoomBranding.bar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .foregroundColor(.white)
                }
                .accessibilityLabel(GreenRoomBranding.adlib)
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
        .navigationDestination(item: $selectedProfile) { wrapper in
            UserProfileDetailView(userId: wrapper.id, initialUser: wrapper.initialUser)
        }
    }
}

// MARK: - Profile Navigation Wrapper

private struct ProfileNavigationWrapper: Identifiable, Hashable {
    let id: UUID
    let initialUser: UserSummary?
    
    init(userId: UUID, initialUser: UserSummary? = nil) {
        self.id = userId
        self.initialUser = initialUser
    }
}
