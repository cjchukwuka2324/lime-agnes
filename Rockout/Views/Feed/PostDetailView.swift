import SwiftUI

struct PostDetailView: View {
    let postId: String
    let service: FeedService
    
    @StateObject private var viewModel: PostDetailViewModel
    @State private var showComposer = false
    
    init(postId: String, service: FeedService = InMemoryFeedService.shared) {
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
                        FeedCardView(post: rootPost)
                        
                        // Replies Section
                        if !viewModel.replies.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Replies")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                
                                ForEach(viewModel.replies) { reply in
                                    FeedCardView(post: reply, isReply: true)
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
                ) {
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
