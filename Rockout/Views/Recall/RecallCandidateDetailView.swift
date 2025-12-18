import SwiftUI

struct RecallCandidateDetailView: View {
    let candidate: RecallCandidateData
    let sources: [RecallSource]
    let songUrl: String?
    let onConfirm: () -> Void
    let onNotIt: () -> Void
    let onReprompt: ((String) -> Void)?
    
    @Environment(\.dismiss) var dismiss
    @State private var showRepromptSheet = false
    @State private var repromptText = ""
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
                                        .fill(confidenceColor)
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
                                Button {
                                    if let urlString = songUrl,
                                       let url = URL(string: urlString) {
                                        UIApplication.shared.open(url)
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
                                    shareSong()
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.title2)
                                        Text("Share")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white)
                                }
                                
                                if onReprompt != nil {
                                    Button {
                                        showRepromptSheet = true
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.title2)
                                            Text("Refine")
                                                .font(.caption)
                                        }
                                        .foregroundColor(.white)
                                    }
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
            .sheet(isPresented: $showRepromptSheet) {
                RecallRepromptSheet(
                    originalQuery: "\(candidate.title) by \(candidate.artist)",
                    onReprompt: { text in
                        showRepromptSheet = false
                        onReprompt?(text)
                    }
                )
            }
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

