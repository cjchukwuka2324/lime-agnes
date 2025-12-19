import SwiftUI

struct RecallMessageBubble: View {
    let message: RecallMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            Group {
                switch message.messageType {
                case .text, .voice:
                    userMessageView
                case .image:
                    imageMessageView
                case .status:
                    statusMessageView
                case .candidate:
                    if let candidate = message.candidate {
                        RecallCandidateCard(
                            candidate: candidate,
                            sources: message.sourcesJson,
                            songUrl: message.songUrl,
                            onOpenSong: {
                                if let urlString = message.songUrl,
                                   let url = URL(string: urlString) {
                                    UIApplication.shared.open(url)
                                }
                            },
                            onConfirm: {
                                // Handle confirm
                            },
                            onNotIt: {
                                // Handle dismiss
                            }
                        )
                    } else {
                        Text(message.text ?? "Unknown message")
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var userMessageView: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            if message.messageType == .voice {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                    Text("Voice note")
                        .font(.subheadline)
                }
            } else {
                Text(message.text ?? "")
                    .font(.body)
            }
            
            Text(message.createdAt.timeAgoDisplay())
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(message.role == .user ? Color(hex: "#1ED760") : Color.white.opacity(0.1))
        )
        .foregroundColor(message.role == .user ? .white : .white)
    }
    
    private var imageMessageView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let mediaPath = message.mediaPath {
                AsyncImage(url: URL(string: mediaPath)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 200)
                        .overlay {
                            ProgressView()
                        }
                }
                .frame(maxHeight: 200)
                .cornerRadius(12)
            }
            
            Text(message.createdAt.timeAgoDisplay())
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#1ED760"))
        )
    }
    
    private var statusMessageView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(message.text ?? "Searching...")
                .font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
        .foregroundColor(.white)
    }
}








