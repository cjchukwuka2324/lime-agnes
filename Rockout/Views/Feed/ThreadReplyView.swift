import SwiftUI

struct ThreadReplyView: View {
    let post: Post
    let allReplies: [Post]
    let onLike: ((String) -> Void)?
    let onDelete: ((String) -> Void)?
    let onTapProfile: ((UserSummary) -> Void)?
    let onMentionTap: ((String) -> Void)?
    let service: FeedService
    let level: Int
    
    @State private var showReplyComposer = false
    @State private var isExpanded = true
    
    private let maxVisualIndent = 5
    private var actualIndent: Int {
        min(level, maxVisualIndent)
    }
    
    private var replies: [Post] {
        allReplies.filter { $0.parentPostId == post.id }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reply content with indent
            HStack(alignment: .top, spacing: 0) {
                // Indent lines
                if level > 0 {
                    ForEach(0..<actualIndent, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 2)
                            .padding(.leading, 12)
                    }
                }
                
                // Reply card
                VStack(alignment: .leading, spacing: 8) {
                    FeedCardView(
                        post: post,
                        isReply: true,
                        onLike: onLike,
                        onReply: { _ in
                            showReplyComposer = true
                        },
                        onNavigateToParent: nil,
                        onTapProfile: onTapProfile,
                        onDelete: onDelete,
                        onMentionTap: onMentionTap,
                        showInlineReplies: false,
                        service: service
                    )
                    
                    // Reply button for this reply
                    if !replies.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                Text("\(replies.count) \(replies.count == 1 ? "reply" : "replies")")
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.1))
                            )
                        }
                        .padding(.leading, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Nested replies (recursive)
            if isExpanded && !replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(replies) { reply in
                        ThreadReplyView(
                            post: reply,
                            allReplies: allReplies,
                            onLike: onLike,
                            onDelete: onDelete,
                            onTapProfile: onTapProfile,
                            onMentionTap: onMentionTap,
                            service: service,
                            level: level + 1
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showReplyComposer) {
            NavigationStack {
                PostComposerView(
                    service: service,
                    parentPost: post,
                    onPostCreated: { createdPostId in
                        showReplyComposer = false
                    }
                )
            }
        }
    }
}
