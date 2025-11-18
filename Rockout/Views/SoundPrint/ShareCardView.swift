import SwiftUI

struct ShareCardView: View {
    let profile: SpotifyUserProfile?
    let artists: [SpotifyArtist]
    let tracks: [SpotifyTrack]
    let genres: [(genre: String, percent: Double)]
    let gradient: LinearGradient
    let preloadedImages: [URL: UIImage]   // PRELOADED

    var body: some View {
        ZStack {
            gradient.ignoresSafeArea()

            VStack(spacing: 24) {
                
                // Profile row
                if let url = profile?.imageURL,
                   let img = preloadedImages[url] {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                }

                Text(profile?.display_name ?? "RockOut Listener")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Your SoundPrint • 2025")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))

                // Artists
                HStack(spacing: 16) {
                    ForEach(artists.prefix(5)) { artist in
                        if let url = artist.imageURL,
                           let img = preloadedImages[url] {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        }
                    }
                }

                // Genre bars
                VStack(spacing: 12) {
                    ForEach(genres, id: \.genre) { g in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.green)
                                    .frame(width: 300 * g.percent)
                            )
                            .frame(height: 14)
                    }
                }

                Spacer()
            }
            .padding(40)
        }
        .frame(width: 1080, height: 1920)
    }
}
