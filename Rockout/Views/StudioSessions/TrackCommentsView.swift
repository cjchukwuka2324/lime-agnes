import SwiftUI

struct TrackCommentsView: View {
    let track: StudioTrackRecord
    @Binding var comments: [TrackComment]
    @ObservedObject var playerVM: AudioPlayerViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                if comments.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No comments yet")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.7))
                        Text("Be the first to comment on this track")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(comments) { comment in
                                CommentRow(comment: comment, playerVM: playerVM)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

// MARK: - Comment Row
struct CommentRow: View {
    let comment: TrackComment
    @ObservedObject var playerVM: AudioPlayerViewModel
    
    var body: some View {
        Button {
            // Seek to comment timestamp
            playerVM.seek(to: comment.timestamp)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Timestamp badge
                VStack {
                    Text(formatTime(comment.timestamp))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white)
                        )
                }
                .frame(width: 50)
                
                // Comment content
                VStack(alignment: .leading, spacing: 4) {
                    Text(comment.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Text(comment.content)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(formatDate(comment.createdAt))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else {
            return "0:00"
        }
        
        let validTime = max(0, time)
        let minutes = Int(validTime) / 60
        let seconds = Int(validTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
