import SwiftUI

struct MoodDJCard: View {
    let recommendation: MoodRecommendation
    let onPlay: () -> Void
    let onShare: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with play button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(recommendation.artist)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                        .foregroundColor(Color(hex: "#1ED760"))
                }
            }
            
            // Vibe tags
            if !recommendation.vibeTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recommendation.vibeTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .foregroundColor(Color(hex: "#1ED760"))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#1ED760").opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                }
            }
            
            // Why it fits
            if let whyItFits = recommendation.whyItFits {
                Text(whyItFits)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(3)
            }
            
            // Confidence indicator
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Circle()
                        .fill(index < Int(recommendation.confidence * 5) ? Color(hex: "#1ED760") : Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
                Text("\(Int(recommendation.confidence * 100))% match")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            // Actions
            HStack(spacing: 16) {
                Button(action: onShare) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                }
                
                Button(action: onSave) {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark")
                        Text("Save")
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                // Links
                if let spotifyUrl = recommendation.spotifyUrl, let url = URL(string: spotifyUrl) {
                    Link(destination: url) {
                        Image(systemName: "music.note")
                            .foregroundColor(Color(hex: "#1ED760"))
                    }
                }
                
                if let appleMusicUrl = recommendation.appleMusicUrl, let url = URL(string: appleMusicUrl) {
                    Link(destination: url) {
                        Image(systemName: "music.note.list")
                            .foregroundColor(Color(hex: "#1ED760"))
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

struct MoodRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let confidence: Double
    let vibeTags: [String]
    let whyItFits: String?
    let spotifyUrl: String?
    let appleMusicUrl: String?
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 12) {
                MoodDJCard(
                    recommendation: MoodRecommendation(
                        title: "Good Vibrations",
                        artist: "The Beach Boys",
                        confidence: 0.9,
                        vibeTags: ["happy", "energetic", "summer"],
                        whyItFits: "This upbeat classic perfectly matches your energetic mood with its infectious melody and positive vibes.",
                        spotifyUrl: "https://open.spotify.com/track/example",
                        appleMusicUrl: nil
                    ),
                    onPlay: {},
                    onShare: {},
                    onSave: {}
                )
            }
            .padding()
        }
    }
}




