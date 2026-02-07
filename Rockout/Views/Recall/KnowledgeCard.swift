import SwiftUI

struct KnowledgeCard: View {
    let answer: String
    let sources: [RecallSource]
    let relatedSongs: [RelatedSong]?
    let uncertaintyNoted: Bool
    let onOpenSource: (URL) -> Void
    
    @State private var showSources = false
    @State private var expanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(Color(hex: "#1ED760"))
                Text("Knowledge Answer")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            // Uncertainty notice
            if uncertaintyNoted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("I'm not entirely sure about this answer")
                        .font(.caption)
                        .foregroundColor(.yellow.opacity(0.9))
                }
                .padding(8)
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
            }
            
            // Answer text
            Text(answer)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(expanded ? nil : 4)
                .animation(.easeInOut, value: expanded)
            
            if answer.count > 200 {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation {
                        expanded.toggle()
                    }
                }
                .font(.caption)
                .foregroundColor(Color(hex: "#1ED760"))
            }
            
            // Related songs
            if let relatedSongs = relatedSongs, !relatedSongs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Related Songs")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    
                    ForEach(relatedSongs.prefix(3), id: \.title) { song in
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .foregroundColor(Color(hex: "#1ED760"))
                            Text("\(song.title) by \(song.artist)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.top, 8)
            }
            
            // Sources
            if !sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: { showSources.toggle() }) {
                        HStack {
                            Text("\(sources.count) Source\(sources.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .foregroundColor(Color(hex: "#1ED760"))
                            Image(systemName: showSources ? "chevron.up" : "chevron.down")
                                .foregroundColor(Color(hex: "#1ED760"))
                                .font(.caption)
                        }
                    }
                    
                    if showSources {
                        ForEach(sources, id: \.url) { source in
                            SourceRow(source: source) {
                                if let url = URL(string: source.url) {
                                    onOpenSource(url)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct SourceRow: View {
    let source: RecallSource
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .foregroundColor(Color(hex: "#1ED760"))
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    
                    if let publisher = source.publisher {
                        Text(publisher)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(.gray)
            }
            .padding(8)
            .background(Color.white.opacity(0.03))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Using RelatedSong from RecallModels.swift
// This local definition is removed to avoid ambiguity

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        KnowledgeCard(
            answer: "Bohemian Rhapsody was written by Freddie Mercury for the British rock band Queen. It was released in 1975 as part of their album 'A Night at the Opera'. The song is notable for its unusual structure, combining ballad, opera, and hard rock sections.",
            sources: [
                RecallSource(title: "Wikipedia - Bohemian Rhapsody", url: "https://en.wikipedia.org/wiki/Bohemian_Rhapsody", snippet: nil, publisher: "Wikipedia")
            ],
            relatedSongs: [
                RelatedSong(title: "We Are The Champions", artist: "Queen"),
                RelatedSong(title: "Don't Stop Me Now", artist: "Queen")
            ],
            uncertaintyNoted: false,
            onOpenSource: { _ in }
        )
        .padding()
    }
}















