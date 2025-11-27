import SwiftUI

struct LeaderboardAttachmentView: View {
    let entry: LeaderboardEntrySummary
    let onTap: (() -> Void)?
    
    init(entry: LeaderboardEntrySummary, onTap: (() -> Void)? = nil) {
        self.entry = entry
        self.onTap = onTap
    }
    
    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
            // Artist Image
            if let imageURL = entry.artistImageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
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
                            Image(systemName: "music.note")
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
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
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
            
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.artistName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text(entry.userDisplayName)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text(entry.percentileLabel)
                            .font(.caption.weight(.medium))
                            .foregroundColor(Color(hex: "#1ED760"))
                        
                        Text("• Rank #\(entry.rank)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
