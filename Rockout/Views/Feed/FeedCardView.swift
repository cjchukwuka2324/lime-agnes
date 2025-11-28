import SwiftUI

struct FeedCardView: View {
    let post: Post
    let isReply: Bool
    let onLike: ((String) -> Void)?
    let onReply: ((Post) -> Void)?
    let onNavigateToParent: ((String) -> Void)?
    let onNavigateToRockList: ((String) -> Void)?
    let showInlineReplies: Bool
    let service: FeedService?
    
    @State private var showReplyComposer = false
    @State private var replies: [Post] = []
    @State private var isLoadingReplies = false
    @State private var isExpanded = false
    @State private var showFullScreenImage = false
    
    init(
        post: Post,
        isReply: Bool = false,
        onLike: ((String) -> Void)? = nil,
        onReply: ((Post) -> Void)? = nil,
        onNavigateToParent: ((String) -> Void)? = nil,
        onNavigateToRockList: ((String) -> Void)? = nil,
        showInlineReplies: Bool = false,
        service: FeedService? = nil
    ) {
        self.post = post
        self.isReply = isReply
        self.onLike = onLike
        self.onReply = onReply
        self.onNavigateToParent = onNavigateToParent
        self.onNavigateToRockList = onNavigateToRockList
        self.showInlineReplies = showInlineReplies
        self.service = service
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Parent Post Reference (for replies in timeline)
            if let parentSummary = post.parentPostSummary, !isReply {
                ParentPostReferenceView(parentPost: parentSummary) {
                    if let parentPostId = post.parentPostId {
                        onNavigateToParent?(parentPostId)
                    }
                }
                .padding(.bottom, 16)
            }
            
            // Author Info
            HStack(spacing: 12) {
                // Avatar
                Group {
                    if let pictureURL = post.author.profilePictureURL {
                        AsyncImage(url: pictureURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .tint(.white)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                avatarFallback
                            @unknown default:
                                avatarFallback
                            }
                        }
                    } else {
                        avatarFallback
                    }
                }
                .frame(width: isReply ? 40 : 50, height: isReply ? 40 : 50)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(post.author.displayName)
                            .font(isReply ? .subheadline.weight(.bold) : .headline.weight(.bold))
                            .foregroundColor(.white)
                        
                        if post.parentPostId != nil && !isReply {
                            Text("replied")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                )
                        }
                    }
                    
                    Text(post.author.handle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Text(post.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.bottom, 16)
            
            // Leaderboard Attachment
            if let leaderboardEntry = post.leaderboardEntry {
                LeaderboardAttachmentView(entry: leaderboardEntry) {
                    if let onNavigateToRockList = onNavigateToRockList {
                        onNavigateToRockList(leaderboardEntry.artistId)
                    }
                }
                .padding(.bottom, 16)
            }
            
            // Post Content
            if !post.text.isEmpty {
                Text(post.text)
                    .font(isReply ? .body : .body)
                    .foregroundColor(.white.opacity(0.95))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)
            }
            
            // Media Attachments
            if let imageURL = post.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 250)
                            .overlay(
                                ProgressView()
                                    .tint(.white)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxHeight: 450)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .onTapGesture {
                                showFullScreenImage = true
                            }
                    case .failure:
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 250)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .padding(.bottom, 16)
            }
            
            // Video Attachment
            if let videoURL = post.videoURL {
                VideoPlayerView(videoURL: videoURL)
                    .frame(maxHeight: 450)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.bottom, 16)
            }
            
            // Audio Attachment
            if let audioURL = post.audioURL {
                FeedAudioPlayerView(audioURL: audioURL)
                    .padding(.bottom, 16)
            }
            
            // Reshared Post (if resharedPostId is set, we could fetch and display it here)
            // For MVP, we'll skip displaying reshared posts to avoid circular dependencies
            
            // Action Buttons (Like, Reply)
            if !isReply {
                HStack(spacing: 0) {
                    // Like Button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            onLike?(post.id)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: post.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(post.isLiked ? Color(hex: "#1ED760") : .white.opacity(0.7))
                                .symbolEffect(.bounce, value: post.isLiked)
                            if post.likeCount > 0 {
                                Text("\(post.likeCount)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(post.isLiked ? Color(hex: "#1ED760") : .white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(post.isLiked ? Color(hex: "#1ED760").opacity(0.2) : Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                        .frame(width: 12)
                    
                    // Reply Button
                    Button {
                        if showInlineReplies {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isExpanded.toggle()
                            }
                            if isExpanded && replies.isEmpty {
                                Task {
                                    await loadReplies()
                                }
                            }
                        } else {
                            onReply?(post)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            if post.replyCount > 0 {
                                Text("\(post.replyCount)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            
            // Inline Replies Section
            if showInlineReplies && isExpanded && !isReply {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .background(Color.white.opacity(0.15))
                        .padding(.vertical, 8)
                    
                    if isLoadingReplies {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.9)
                            Text("Loading replies...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    } else if replies.isEmpty {
                        HStack {
                            Text("No replies yet")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(replies) { reply in
                                FeedCardView(post: reply, isReply: true)
                            }
                        }
                    }
                    
                    // Reply Input Button
                    Button {
                        showReplyComposer = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color(hex: "#1ED760"))
                            Text("Add a reply...")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color.white.opacity(0.12))
                        )
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 16)
            }
        }
        .padding(isReply ? 16 : 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .sheet(isPresented: $showReplyComposer) {
            PostComposerView(
                service: service ?? InMemoryFeedService.shared,
                parentPost: post
            ) {
                Task {
                    await loadReplies()
                    NotificationCenter.default.post(name: .feedDidUpdate, object: nil)
                }
            }
        }
        .sheet(isPresented: $showFullScreenImage) {
            if let imageURL = post.imageURL {
                FullScreenImageViewSheet(imageURL: imageURL)
            }
        }
    }
    
            private func loadReplies() async {
                guard let service = service else { return }
                isLoadingReplies = true
                defer { isLoadingReplies = false }
                
                do {
                    replies = try await service.fetchReplies(for: post.id)
                } catch {
                    print("Failed to load replies: \(error)")
                }
            }
            
            private var avatarFallback: some View {
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
                        Text(post.author.avatarInitials)
                            .font(isReply ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    )
            }
        }

// MARK: - Full Screen Image View

struct FullScreenImageViewSheet: View {
    let imageURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = lastScale * value
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        if scale < 1.0 {
                                            withAnimation {
                                                scale = 1.0
                                                lastScale = 1.0
                                            }
                                        } else if scale > 3.0 {
                                            withAnimation {
                                                scale = 3.0
                                                lastScale = 3.0
                                            }
                                        }
                                    }
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                    case .failure:
                        VStack(spacing: 16) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.5))
                            Text("Failed to load image")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
        }
    }
}
