import SwiftUI

/// Autocomplete dropdown for #hashtags
struct HashtagAutocompleteView: View {
    let suggestions: [TrendingHashtag]
    let onSelect: (TrendingHashtag) -> Void
    
    var body: some View {
        if !suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(suggestions.prefix(5)) { hashtag in
                    Button {
                        onSelect(hashtag)
                    } label: {
                        HStack(spacing: 12) {
                            // Hashtag icon
                            Image(systemName: "number")
                                .font(.subheadline)
                                .foregroundColor(Color(hex: "#1ED760"))
                                .frame(width: 24, height: 24)
                            
                            // Hashtag text and post count
                            VStack(alignment: .leading, spacing: 2) {
                                Text("#\(hashtag.tag)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                
                                Text("\(hashtag.postCount) posts")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.05))
                    }
                    .buttonStyle(.plain)
                    
                    if hashtag.id != suggestions.prefix(5).last?.id {
                        Divider()
                            .background(Color.white.opacity(0.1))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#1a1a1a"))
                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

