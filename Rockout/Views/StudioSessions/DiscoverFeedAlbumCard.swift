import SwiftUI

struct DiscoverFeedAlbumCard: View {
    let album: StudioAlbumRecord
    let isSaved: Bool
    let onSave: () -> Void
    let onUnsave: () -> Void
    
    var body: some View {
        NavigationLink {
            AlbumDetailView(album: album, deleteContext: nil)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Cover Art
                Group {
                    if let urlString = album.cover_art_url,
                       let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                albumPlaceholder
                            case .success(let image):
                                ZStack(alignment: .topTrailing) {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                    
                                    // Save button overlay
                                    Button {
                                        if isSaved {
                                            onUnsave()
                                        } else {
                                            onSave()
                                        }
                                    } label: {
                                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .padding(8)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                    .padding(8)
                                }
                            case .failure:
                                albumPlaceholder
                            @unknown default:
                                albumPlaceholder
                            }
                        }
                    } else {
                        ZStack(alignment: .topTrailing) {
                            albumPlaceholder
                            
                            // Save button overlay
                            Button {
                                if isSaved {
                                    onUnsave()
                                } else {
                                    onSave()
                                }
                            } label: {
                                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .padding(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                
                // Album Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let artistName = album.artist_name, !artistName.isEmpty {
                        Text(artistName)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    
                    // Public badge
                    if album.is_public == true {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.caption2)
                            Text("Public")
                                .font(.caption2)
                        }
                        .foregroundColor(.green)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
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

