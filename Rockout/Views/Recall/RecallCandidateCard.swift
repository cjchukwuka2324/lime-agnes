import SwiftUI

struct RecallCandidateCard: View {
    let candidate: RecallCandidateData
    let sources: [RecallSource]
    let songUrl: String?
    let onOpenSong: () -> Void
    let onConfirm: () -> Void
    let onNotIt: () -> Void
    let onReprompt: ((String) -> Void)?
    let onAskGreenRoom: (() -> Void)? // CTA for low confidence
    
    @State private var showSources = false
    @State private var showDetail = false
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
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
            
            // Background
            if let background = candidate.background {
                Text(background)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(2)
                    .padding(.top, 4)
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
                Menu {
                    Button {
                        // Open Apple Music
                        let query = "\(candidate.title) \(candidate.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "https://music.apple.com/search?term=\(query)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Apple Music", systemImage: "music.note")
                    }
                    
                    Button {
                        // Open Spotify
                        let query = "\(candidate.title) \(candidate.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "https://open.spotify.com/search/\(query)") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Spotify", systemImage: "music.note.list")
                    }
                    
                    if let urlString = songUrl, let url = URL(string: urlString) {
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Label("Original Link", systemImage: "link")
                        }
                    }
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
            
            // Ask GreenRoom CTA for low confidence
            if candidate.confidence < 0.65, let onAskGreenRoom = onAskGreenRoom {
                Button {
                    onAskGreenRoom()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 14))
                        Text("Ask the crowd in GreenRoom")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.7))
                    )
                }
                .padding(.top, 8)
                .accessibilityLabel("Ask the crowd in GreenRoom")
                .accessibilityHint("Double tap to post this query to GreenRoom for community help")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSources) {
            RecallSourcesSheet(sources: sources)
        }
        .sheet(isPresented: $showDetail) {
            CandidateDetailSheet(
                candidate: candidate,
                sources: sources,
                songUrl: songUrl,
                onConfirm: {
                    showDetail = false
                    onConfirm()
                },
                onNotIt: {
                    showDetail = false
                    onNotIt()
                },
                onReprompt: onReprompt
            )
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

// MARK: - Candidate Detail Sheet (Inline to avoid separate file dependency)

private struct CandidateDetailSheet: View {
    let candidate: RecallCandidateData
    let sources: [RecallSource]
    let songUrl: String?
    let onConfirm: () -> Void
    let onNotIt: () -> Void
    let onReprompt: ((String) -> Void)?
    
    @Environment(\.dismiss) var dismiss
    @State private var showSources = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Title and Artist
                        VStack(spacing: 8) {
                            Text(candidate.title)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            Text(candidate.artist)
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.top, 20)
                        
                        // Confidence bar
                        VStack(spacing: 8) {
                            Text("\(Int(candidate.confidence * 100))% confidence")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 8)
                                        .cornerRadius(4)
                                    
                                    Rectangle()
                                        .fill(detailConfidenceColor)
                                        .frame(width: geometry.size.width * CGFloat(candidate.confidence), height: 8)
                                        .cornerRadius(4)
                                }
                            }
                            .frame(height: 8)
                        }
                        .padding(.horizontal, 20)
                        
                        // Reason
                        if let reason = candidate.reason {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Why it matched")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text(reason)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Background
                        if let background = candidate.background {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("About this song")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text(background)
                                    .font(.body)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Lyric snippet
                        if let snippet = candidate.lyricSnippet, !snippet.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Lyric snippet")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text("\"\(snippet)\"")
                                    .font(.body)
                                    .italic()
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Actions
                        VStack(spacing: 16) {
                            // Primary actions
                            HStack(spacing: 16) {
                                Button {
                                    onConfirm()
                                } label: {
                                    Text("Confirm")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color(hex: "#1ED760"))
                                        )
                                }
                                
                                Button {
                                    onNotIt()
                                } label: {
                                    Text("Not it")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color.white.opacity(0.2))
                                        )
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Secondary actions
                            HStack(spacing: 20) {
                                Menu {
                                    Button {
                                        // Open Apple Music
                                        let query = "\(candidate.title) \(candidate.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                        if let url = URL(string: "https://music.apple.com/search?term=\(query)") {
                                            UIApplication.shared.open(url)
                                        }
                                    } label: {
                                        Label("Apple Music", systemImage: "music.note")
                                    }
                                    
                                    Button {
                                        // Open Spotify
                                        let query = "\(candidate.title) \(candidate.artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                        if let url = URL(string: "https://open.spotify.com/search/\(query)") {
                                            UIApplication.shared.open(url)
                                        }
                                    } label: {
                                        Label("Spotify", systemImage: "music.note.list")
                                    }
                                    
                                    if let urlString = songUrl, let url = URL(string: urlString) {
                                        Button {
                                            UIApplication.shared.open(url)
                                        } label: {
                                            Label("Original Link", systemImage: "link")
                                        }
                                    }
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "music.note")
                                            .font(.title2)
                                        Text("Open Song")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                }
                                
                                Button {
                                    showSources = true
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "link")
                                            .font(.title2)
                                        Text("Sources")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                }
                                
                                Button {
                                    detailShareSong()
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.title2)
                                        Text("Share")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Song Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showSources) {
                RecallSourcesSheet(sources: sources)
            }
        }
    }
    
    private var detailConfidenceColor: Color {
        if candidate.confidence >= 0.85 {
            return Color(hex: "#1ED760")
        } else if candidate.confidence >= 0.60 {
            return Color.orange
        } else {
            return Color.yellow
        }
    }
    
    private func detailShareSong() {
        let text = "\(candidate.title) by \(candidate.artist)"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
}

