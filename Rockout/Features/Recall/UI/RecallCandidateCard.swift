import SwiftUI

struct RecallCandidateCard: View {
    let candidate: RecallCandidateData
    let sources: [RecallSource]
    let songUrl: String?
    let onOpenSong: () -> Void
    let onConfirm: () -> Void
    let onNotIt: () -> Void
    
    @State private var showSources = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and Artist
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(candidate.artist)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Confidence bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(Int(candidate.confidence * 100))% confidence")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 6)
                            .cornerRadius(3)
                        
                        Rectangle()
                            .fill(confidenceColor)
                            .frame(width: geometry.size.width * CGFloat(candidate.confidence), height: 6)
                            .cornerRadius(3)
                    }
                }
                .frame(height: 6)
            }
            
            // Reason
            if let reason = candidate.reason {
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            
            // Lyric snippet
            if let snippet = candidate.lyricSnippet, !snippet.isEmpty {
                Text("\"\(snippet)\"")
                    .font(.caption)
                    .italic()
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Actions
            HStack(spacing: 12) {
                Button {
                    onOpenSong()
                } label: {
                    Label("Open Song", systemImage: "music.note")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                
                Button {
                    showSources = true
                } label: {
                    Label("Sources", systemImage: "link")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                
                Button {
                    shareSong()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button {
                    onConfirm()
                } label: {
                    Text("Confirm")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#1ED760"))
                        )
                }
                
                Button {
                    onNotIt()
                } label: {
                    Text("Not it")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showSources) {
            RecallSourcesSheet(sources: sources)
        }
    }
    
    private var confidenceColor: Color {
        if candidate.confidence >= 0.85 {
            return Color(hex: "#1ED760")
        } else if candidate.confidence >= 0.60 {
            return Color.orange
        } else {
            return Color.yellow
        }
    }
    
    private func shareSong() {
        let text = "\(candidate.title) by \(candidate.artist)"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}


















