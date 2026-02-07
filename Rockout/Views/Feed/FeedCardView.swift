import SwiftUI
import Supabase
import Foundation
import AVFoundation

struct FeedCardView: View {
    let post: Post
    let isReply: Bool
    let onLike: ((String) -> Void)?
    let onReply: ((Post) -> Void)?
    let onEcho: ((String) -> Void)?
    let onEchoWithCommentary: ((String) -> Void)?
    let onNavigateToParent: ((String) -> Void)?
    let onTapProfile: (() -> Void)?
    let onDelete: ((String) -> Void)?
    let onHashtagTap: ((String) -> Void)?
    let onMentionTap: ((String) -> Void)?
    let showInlineReplies: Bool
    let service: FeedService?
    
    @State private var showReplyComposer = false
    @State private var showEchoActionSheet = false
    @State private var replies: [Post] = []
    @State private var isLoadingReplies = false
    @State private var isExpanded = false
    @State private var showFullScreenMedia = false
    @State private var showDeleteConfirmation = false
    @State private var postToDelete: String?
    @State private var mutablePoll: Poll?
    @State private var originalPost: Post?
    @State private var isLoadingOriginalPost = false
    
    init(
        post: Post,
        isReply: Bool = false,
        onLike: ((String) -> Void)? = nil,
        onReply: ((Post) -> Void)? = nil,
        onEcho: ((String) -> Void)? = nil,
        onEchoWithCommentary: ((String) -> Void)? = nil,
        onNavigateToParent: ((String) -> Void)? = nil,
        onTapProfile: (() -> Void)? = nil,
        onDelete: ((String) -> Void)? = nil,
        onHashtagTap: ((String) -> Void)? = nil,
        onMentionTap: ((String) -> Void)? = nil,
        showInlineReplies: Bool = false,
        service: FeedService? = nil
    ) {
        self.post = post
        self.isReply = isReply
        self.onLike = onLike
        self.onReply = onReply
        self.onEcho = onEcho
        self.onEchoWithCommentary = onEchoWithCommentary
        self.onNavigateToParent = onNavigateToParent
        self.onTapProfile = onTapProfile
        self.onDelete = onDelete
        self.onHashtagTap = onHashtagTap
        self.onMentionTap = onMentionTap
        self.showInlineReplies = showInlineReplies
        self.service = service
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if post.resharedPostId != nil && post.text.isEmpty {
                // This is an echo post - show "Echoed by" indicator and original post
                echoedPostView
            } else {
                // Regular post or echo with comment
                parentPostReference
                if post.resharedPostId != nil {
                    echoedByIndicator
                }
                authorHeader
                leaderboardAttachment
                postContent
                mediaAttachments
                actionButtons
                inlineReplies
            }
        }
        .padding(isReply ? 12 : 14)
        .background(cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showReplyComposer) {
            PostComposerView(
                service: service ?? SupabaseFeedService.shared,
                parentPost: post
            ) { createdPostId in
                Task {
                    await loadReplies()
                    NotificationCenter.default.post(name: .feedDidUpdate, object: nil)
                }
            }
        }
        .fullScreenCover(isPresented: $showFullScreenMedia) {
            FullScreenMediaView(
                imageURLs: post.imageURLs,
                videoURL: post.videoURL,
                initialIndex: 0
            )
        }
        .alert(GreenRoomBranding.Actions.deleteBar, isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                postToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let postId = postToDelete {
                    onDelete?(postId)
                }
                postToDelete = nil
            }
        } message: {
            Text(GreenRoomBranding.Actions.deleteBarMessage)
        }
        .confirmationDialog("Echo Options", isPresented: $showEchoActionSheet, titleVisibility: .visible) {
            Button("Echo") {
                onEcho?(post.id)
            }
            Button("Echo with Commentary") {
                onEchoWithCommentary?(post.id)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var echoedByIndicator: some View {
        Button {
            onTapProfile?()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Text("\(post.author.displayName) \(GreenRoomBranding.echoed)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var echoedPostView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Echo indicator (clickable to view echo author's profile)
            Button {
                onTapProfile?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.2.squarepath")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("\(post.author.displayName) \(GreenRoomBranding.echoed)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            
            // Display full original post if available
            if let originalPostId = post.resharedPostId {
                if let fullOriginalPost = originalPost {
                    // Display the full original post as a nested card with interactions targeting the original post ID
                    FeedCardView(
                        post: fullOriginalPost,
                        isReply: true, // Render as nested/reply style
                        onLike: { _ in
                            // Use original post ID for like/amp action
                            onLike?(originalPostId)
                        },
                        onReply: { parentPost in
                            // Use original post for reply/adlib
                            onReply?(parentPost)
                        },
                        onEcho: { _ in
                            // Use original post ID for echo action
                            onEcho?(originalPostId)
                        },
                        onEchoWithCommentary: { _ in
                            // Use original post ID for echo with commentary
                            onEchoWithCommentary?(originalPostId)
                        },
                        onNavigateToParent: { _ in
                            // Navigate to original post thread
                            onNavigateToParent?(originalPostId)
                        },
                        onTapProfile: onTapProfile,
                        onDelete: onDelete,
                        onHashtagTap: onHashtagTap,
                        onMentionTap: onMentionTap,
                        showInlineReplies: false, // Don't show inline replies in echo view
                        service: service
                    )
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Navigate to original post thread when tapping nested card
                        onNavigateToParent?(originalPostId)
                    }
                } else if let originalPostSummary = post.parentPost {
                    // Use PostSummary to render immediately - this prevents blocking
                    let summaryPost = Post(
                        id: originalPostSummary.id,
                        text: originalPostSummary.text,
                        createdAt: originalPostSummary.createdAt,
                        author: originalPostSummary.author,
                        imageURLs: originalPostSummary.imageURLs,
                        videoURL: originalPostSummary.videoURL,
                        audioURL: nil,
                        likeCount: originalPostSummary.likeCount,
                        replyCount: originalPostSummary.replyCount,
                        isLiked: originalPostSummary.isLiked,
                        echoCount: originalPostSummary.echoCount,
                        isEchoed: originalPostSummary.isEchoed,
                        parentPostId: nil,
                        parentPost: nil,
                        leaderboardEntry: nil,
                        resharedPostId: nil,
                        spotifyLink: nil,
                        poll: nil,
                        backgroundMusic: nil
                    )
                    
                    FeedCardView(
                        post: summaryPost,
                        isReply: true,
                        onLike: { _ in onLike?(originalPostId) },
                        onReply: { parentPost in onReply?(parentPost) },
                        onEcho: { _ in onEcho?(originalPostId) },
                        onEchoWithCommentary: { _ in onEchoWithCommentary?(originalPostId) },
                        onNavigateToParent: { _ in onNavigateToParent?(originalPostId) },
                        onTapProfile: onTapProfile,
                        onDelete: onDelete,
                        onHashtagTap: onHashtagTap,
                        onMentionTap: onMentionTap,
                        showInlineReplies: false,
                        service: service
                    )
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Navigate to original post thread when tapping nested card
                        onNavigateToParent?(originalPostId)
                    }
                    .task(id: originalPostId) {
                        // Fetch full original post in background only once per post ID
                        if originalPost == nil && !isLoadingOriginalPost {
                            await loadOriginalPost(id: originalPostId)
                        }
                    }
                } else {
                    // No parent post data available - show minimal placeholder
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original post")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text(originalPostId)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .task(id: originalPostId) {
                        // Try to fetch the original post
                        if originalPost == nil && !isLoadingOriginalPost {
                            await loadOriginalPost(id: originalPostId)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 12)
    }
    
    private func loadOriginalPost(id: String) async {
        guard let service = service, !isLoadingOriginalPost, originalPost == nil else { return }
        isLoadingOriginalPost = true
        defer { isLoadingOriginalPost = false }
        
        do {
            let fetchedPost = try await service.fetchPostById(id)
            await MainActor.run {
                // Only update if we still don't have the post (avoid race conditions)
                if originalPost == nil {
                    originalPost = fetchedPost
                }
            }
        } catch {
            // Only log if it's not a cancellation error
            if (error as NSError).code != -999 {
                print("⚠️ Failed to load original post: \(error)")
            }
        }
    }
    
    @ViewBuilder
    private var parentPostReference: some View {
        if let parentSummary = post.parentPost, !isReply {
            ParentPostReferenceView(parentPost: parentSummary) {
                if let parentPostId = post.parentPostId {
                    onNavigateToParent?(parentPostId)
                }
            }
            .padding(.bottom, 12)
        }
    }
    
    private var authorHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                avatarButton
                nameHandleButton
                Spacer()
                Text(timeAgoDisplay(for: post.createdAt))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Background music subtitle (subtle, underneath username)
            if let backgroundMusic = post.backgroundMusic {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("\(backgroundMusic.name) - \(backgroundMusic.artist)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    // Mute button
                    // TODO: Implement BackgroundMusicMuteButtonHelper
                    // if backgroundMusic.previewURL != nil {
                    //     BackgroundMusicMuteButtonHelper(backgroundMusic: backgroundMusic)
                    // }
                }
                .padding(.leading, isReply ? 52 : 62) // Align with username
                .padding(.top, 2)
            }
        }
        .padding(.bottom, 12)
    }
    
    private func timeAgoDisplay(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear], from: date, to: now)
        
        if let weeks = components.weekOfYear, weeks > 0 {
            return "\(weeks)w"
        }
        if let days = components.day, days > 0 {
            return "\(days)d"
        }
        if let hours = components.hour, hours > 0 {
            return "\(hours)h"
        }
        if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m"
        }
        return "now"
    }
    
    private var avatarButton: some View {
        Button {
            onTapProfile?()
        } label: {
            Group {
                // If this is a reply to a rank post, show rank owner's profile picture
                // For now, use reply author's picture (this may need backend support)
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
            .frame(width: isReply ? 36 : 44, height: isReply ? 36 : 44)
            .clipShape(Circle())
            .overlay(avatarOverlay)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
    
    private var avatarOverlay: some View {
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
    }
    
    // Computed properties for display name and handle
    private var displayName: String {
        // If this is a reply to a rank post, show the rank owner's name instead of reply author
        if let leaderboardEntry = post.leaderboardEntry,
           isReply,
           post.parentPostId != nil {
            // Show rank owner's name for replies to rank posts
            return leaderboardEntry.userDisplayName
        } else {
            // Show reply author's name for normal replies
            return post.author.displayName
        }
    }
    
    private var displayHandle: String {
        // If this is a reply to a rank post, show the rank owner's handle instead of reply author
        if let leaderboardEntry = post.leaderboardEntry,
           isReply,
           post.parentPostId != nil {
            // Show rank owner's handle for replies to rank posts
            return "@\(leaderboardEntry.userDisplayName.lowercased().replacingOccurrences(of: " ", with: ""))"
        } else {
            // Show reply author's handle for normal replies
            return post.author.handle
        }
    }
    
    private var nameHandleButton: some View {
        Button {
            onTapProfile?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(isReply ? .subheadline.weight(.bold) : .headline.weight(.bold))
                        .foregroundColor(.white)
                    
                    if post.parentPostId != nil && !isReply {
                        Text(GreenRoomBranding.adlibbed.lowercased())
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
                
                Text(displayHandle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private var leaderboardAttachment: some View {
        if let leaderboardEntry = post.leaderboardEntry {
            LeaderboardAttachmentView(entry: leaderboardEntry) {
                // RockList navigation removed - leaderboard entry is now display-only
            }
            .padding(.bottom, 12)
        }
    }
    
    @ViewBuilder
    private var postContent: some View {
        if !post.text.isEmpty {
            MentionHashtagTextView(
                text: post.text,
                font: isReply ? .body : .body,
                textColor: .white.opacity(0.95),
                hashtagColor: Color(hex: "#1ED760"),
                mentionColor: Color(hex: "#1ED760"),
                onHashtagTap: onHashtagTap,
                onMentionTap: onMentionTap
            )
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .padding(.bottom, 12)
        }
    }
    
    @ViewBuilder
    private var mediaAttachments: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Spotify Link - show ABOVE images/videos when both are present
            if let spotifyLink = post.spotifyLink {
                SpotifyLinkCardView(spotifyLink: spotifyLink)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
            }
            
            // Use MediaGridView for Twitter-style grid layout - show AFTER song link
            if !post.imageURLs.isEmpty || post.videoURL != nil {
                MediaGridView(
                    imageURLs: post.imageURLs,
                    videoURL: post.videoURL,
                    onTap: {
                        showFullScreenMedia = true
                    }
                )
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            // Double tap to like
                            handleDoubleTapLike()
                        }
                )
                .padding(.bottom, 12)
            }
            
            if let audioURL = post.audioURL {
                FeedAudioPlayerView(audioURL: audioURL)
                    .padding(.bottom, 12)
            }
            
            // Poll
            if let poll = post.poll {
                PollView(
                    postId: post.id,
                    poll: Binding(
                        get: { mutablePoll ?? poll },
                        set: { newValue in
                            mutablePoll = newValue
                        }
                    ),
                    isOwnPost: post.author.id == SupabaseService.shared.client.auth.currentUser?.id.uuidString
                )
                .onAppear {
                    if mutablePoll == nil {
                        mutablePoll = poll
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        // Ensure action buttons are clearly below media with proper spacing
        // Order: adlib, echo, amp
        HStack(spacing: 0) {
            replyButton  // adlib
            Spacer()
                .frame(width: 12)
            echoButton   // echo
            Spacer()
                .frame(width: 12)
            likeButton   // amp
            Spacer()
                .frame(width: 12)
            deleteButton
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    private var likeButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                onLike?(post.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: post.isLiked ? "bolt.fill" : "bolt")
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
            .accessibilityLabel(post.isLiked ? "\(post.likeCount) \(GreenRoomBranding.amps)" : GreenRoomBranding.ampAction)
        }
        .buttonStyle(.plain)
    }
    
    private var echoButton: some View {
        Button {
            // If echo with commentary callback is available, show action sheet
            if onEchoWithCommentary != nil {
                showEchoActionSheet = true
            } else {
                // Otherwise, just echo directly
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    onEcho?(post.id)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: post.isEchoed ? "arrow.2.squarepath" : "arrow.2.squarepath")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(post.isEchoed ? Color(hex: "#1ED760") : .white.opacity(0.7))
                    .symbolEffect(.bounce, value: post.isEchoed)
                if post.echoCount > 0 {
                    Text("\(post.echoCount)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(post.isEchoed ? Color(hex: "#1ED760") : .white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(post.isEchoed ? Color(hex: "#1ED760").opacity(0.2) : Color.white.opacity(0.1))
            )
            .accessibilityLabel(post.isEchoed ? "\(post.echoCount) \(GreenRoomBranding.echoes)" : GreenRoomBranding.echoAction)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    // Long press always shows action sheet if available
                    if onEchoWithCommentary != nil {
                        showEchoActionSheet = true
                    }
                }
        )
    }
    
    private var replyButton: some View {
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
            .accessibilityLabel(post.replyCount > 0 ? "\(post.replyCount) \(GreenRoomBranding.adlibs)" : GreenRoomBranding.adlibAction)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var deleteButton: some View {
        if let currentUserId = SupabaseService.shared.client.auth.currentUser?.id.uuidString,
           post.author.id == currentUserId {
            Button {
                postToDelete = post.id
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.red.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
    }
    
    @ViewBuilder
    private var inlineReplies: some View {
        if showInlineReplies && isExpanded && !isReply {
            VStack(alignment: .leading, spacing: 16) {
                Divider()
                    .background(Color.white.opacity(0.15))
                    .padding(.vertical, 8)
                
                if isLoadingReplies {
                    loadingRepliesView
                } else if replies.isEmpty {
                    emptyRepliesView
                } else {
                    repliesList
                }
                
                replyInputButton
            }
            .padding(.top, 16)
        }
    }
    
    private var loadingRepliesView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.9)
            Text(GreenRoomBranding.EmptyStates.loadingAdlibs)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
        .padding(.vertical, 12)
    }
    
    private var emptyRepliesView: some View {
        HStack {
            Text(GreenRoomBranding.EmptyStates.noAdlibs)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(.vertical, 12)
    }
    
    private var repliesList: some View {
        VStack(spacing: 12) {
            ForEach(replies) { reply in
                FeedCardView(
                    post: reply,
                    isReply: true,
                    onLike: onLike,
                    onReply: { parentPost in
                        onReply?(parentPost)
                    },
                    onEcho: onEcho,
                    onEchoWithCommentary: onEchoWithCommentary,
                    onNavigateToParent: { parentPostId in
                        onNavigateToParent?(parentPostId)
                    },
                    onTapProfile: onTapProfile,
                    onHashtagTap: onHashtagTap,
                    onMentionTap: onMentionTap,
                    showInlineReplies: false,
                    service: service
                )
            }
        }
    }
    
    private var replyInputButton: some View {
        Button {
            showReplyComposer = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "#1ED760"))
                Text(GreenRoomBranding.addAdlib)
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
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.black)
    }
    
    private func loadReplies() async {
        guard let service = service else { return }
        isLoadingReplies = true
        defer { isLoadingReplies = false }
        
        do {
            let result = try await service.fetchReplies(for: post.id, cursor: nil, limit: 100)
            replies = result.replies
        } catch {
            print("Failed to load replies: \(error)")
        }
    }
    
    private func handleDoubleTapLike() {
        // Trigger like action when double-tapping on media
        onLike?(post.id)
        
        // Provide haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
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
