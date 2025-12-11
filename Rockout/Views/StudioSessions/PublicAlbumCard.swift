import SwiftUI

// MARK: - Public Album Card
struct PublicAlbumCard: View {
    let album: StudioAlbumRecord
    let isSaved: Bool
    let onAddToDiscoveries: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover Art (no overlay buttons)
            NavigationLink {
                AlbumDetailView(album: album, deleteContext: nil)
            } label: {
                Group {
                    if let urlString = album.cover_art_url,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                albumPlaceholder
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                albumPlaceholder
                            @unknown default:
                                albumPlaceholder
                            }
                        }
                    } else {
                        albumPlaceholder
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Album Info
            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                
                if let artistName = album.artist_name, !artistName.isEmpty {
                    Text(artistName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                
                // Public indicator
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("Public")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.top, 2)
            }
            
            // Save/Unsave button below album info
            if !isSaved {
                Button {
                    onAddToDiscoveries()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add to Discoveries")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
            } else {
                Button {
                    onAddToDiscoveries()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Saved")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var albumPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

