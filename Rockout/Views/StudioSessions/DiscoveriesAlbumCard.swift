import SwiftUI

struct DiscoveriesAlbumCard: View {
    let album: StudioAlbumRecord
    let onUnsave: () -> Void
    
    @State private var showUnsaveConfirmation = false
    
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
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                showUnsaveConfirmation = true
            } label: {
                Label("Remove from Discoveries", systemImage: "bookmark.slash")
            }
        }
        .alert("Remove from Discoveries", isPresented: $showUnsaveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                onUnsave()
            }
        } message: {
            Text("Remove \"\(album.title)\" from your discoveries?")
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

