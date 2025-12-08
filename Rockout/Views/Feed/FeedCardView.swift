import SwiftUI
import Supabase
import Foundation
import AVFoundation

struct FeedCardView: View {
    let post: Post
    let isReply: Bool
    let onLike: ((String) -> Void)?
    let onReply: ((Post) -> Void)?
    let onNavigateToParent: ((String) -> Void)?
    let onNavigateToRockList: ((String) -> Void)?
    let onTapProfile: (() -> Void)?
    let onDelete: ((String) -> Void)?
    let onHashtagTap: ((String) -> Void)?
    let showInlineReplies: Bool
    let service: FeedService?
    
    @State private var showReplyComposer = false
    @State private var replies: [Post] = []
    @State private var isLoadingReplies = false
    @State private var isExpanded = false
    @State private var showFullScreenMedia = false
    @State private var showDeleteConfirmation = false
    @State private var postToDelete: String?
    @State private var mutablePoll: Poll?
    
    init(
        post: Post,
        isReply: Bool = false,
        onLike: ((String) -> Void)? = nil,
        onReply: ((Post) -> Void)? = nil,
        onNavigateToParent: ((String) -> Void)? = nil,
        onNavigateToRockList: ((String) -> Void)? = nil,
        onTapProfile: (() -> Void)? = nil,
        onDelete: ((String) -> Void)? = nil,
        onHashtagTap: ((String) -> Void)? = nil,
        showInlineReplies: Bool = false,
        service: FeedService? = nil
    ) {
        self.post = post
        self.isReply = isReply
        self.onLike = onLike
        self.onReply = onReply
        self.onNavigateToParent = onNavigateToParent
        self.onNavigateToRockList = onNavigateToRockList
        self.onTapProfile = onTapProfile
        self.onDelete = onDelete
        self.onHashtagTap = onHashtagTap
        self.showInlineReplies = showInlineReplies
        self.service = service
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            parentPostReference
            authorHeader
            leaderboardAttachment
            postContent
            mediaAttachments
            actionButtons
            inlineReplies
        }
        .padding(isReply ? 16 : 20)
        .background(cardBackground)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
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
        .alert("Delete Post", isPresented: $showDeleteConfirmation) {
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
            Text("Are you sure you want to delete this post? This action cannot be undone.")
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private var parentPostReference: some View {
        if let parentSummary = post.parentPost, !isReply {
            ParentPostReferenceView(parentPost: parentSummary) {
                if let parentPostId = post.parentPostId {
                    onNavigateToParent?(parentPostId)
                }
            }
            .padding(.bottom, 16)
        }
    }
    
    private var authorHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
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
                        .lineLimit(1)
                    
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
        .padding(.bottom, 16)
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
            .frame(width: isReply ? 40 : 50, height: isReply ? 40 : 50)
            .clipShape(Circle())
            .overlay(avatarOverlay)
        }
        .buttonStyle(.plain)
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
                
                Text(displayHandle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var leaderboardAttachment: some View {
        if let leaderboardEntry = post.leaderboardEntry {
            LeaderboardAttachmentView(entry: leaderboardEntry) {
                if let onNavigateToRockList = onNavigateToRockList {
                    onNavigateToRockList(leaderboardEntry.artistId)
                }
            }
            .padding(.bottom, 16)
        }
    }
    
    @ViewBuilder
    private var postContent: some View {
        if !post.text.isEmpty {
            HashtagTextView(
                text: post.text,
                font: isReply ? .body : .body,
                textColor: .white.opacity(0.95),
                hashtagColor: Color(hex: "#1ED760"),
                onHashtagTap: onHashtagTap
            )
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 16)
        }
    }
    
    @ViewBuilder
    private var mediaAttachments: some View {
        if !post.imageURLs.isEmpty {
            ZStack(alignment: .bottomTrailing) {
                ImageSlideshowView(imageURLs: post.imageURLs)
                    .onTapGesture(count: 2) {
                        // Double tap to like
                        handleDoubleTapLike()
                    }
                    .onTapGesture(count: 1) {
                        // Single tap to open full screen
                        showFullScreenMedia = true
                    }
            }
            .padding(.bottom, 16)
        }
        
        if let videoURL = post.videoURL {
            FeedVideoPlayerView(videoURL: videoURL)
                .onTapGesture {
                    // Tap to open full screen (built-in fullscreen button also works)
                    showFullScreenMedia = true
                }
            .frame(maxWidth: .infinity)
            .aspectRatio(16/9, contentMode: .fill)
            .frame(maxHeight: 450)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        // Double tap to like
                        handleDoubleTapLike()
                    }
            )
            .onTapGesture {
                // Single tap to open full screen (still works for tap anywhere)
                showFullScreenMedia = true
            }
            .padding(.bottom, 16)
        }
        
        if let audioURL = post.audioURL {
            FeedAudioPlayerView(audioURL: audioURL)
                .padding(.bottom, 16)
        }
        
        // Spotify Link
        if let spotifyLink = post.spotifyLink {
            SpotifyLinkCardView(spotifyLink: spotifyLink)
                .padding(.horizontal, 4)
                .padding(.bottom, 16)
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
            .padding(.bottom, 16)
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 0) {
            likeButton
            Spacer()
                .frame(width: 12)
            replyButton
            Spacer()
                .frame(width: 12)
            deleteButton
            Spacer()
        }
        .padding(.top, 8)
    }
    
    private var likeButton: some View {
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
            Text("Loading replies...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
        }
        .padding(.vertical, 12)
    }
    
    private var emptyRepliesView: some View {
        HStack {
            Text("No replies yet")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(.vertical, 12)
    }
    
    private var repliesList: some View {
        VStack(spacing: 12) {
            ForEach(replies) { reply in
                FeedCardView(post: reply, isReply: true)
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
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.black)
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
