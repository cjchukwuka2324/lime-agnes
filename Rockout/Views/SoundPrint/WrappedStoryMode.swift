import SwiftUI

struct WrappedStoryMode: View {
    let profile: SpotifyUserProfile?
    let artists: [SpotifyArtist]
    let tracks: [SpotifyTrack]
    let genres: [(genre: String, percent: Double)]
    let personality: FanPersonality?

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private var topGenre: (String, Double)? {
        genres.max(by: { $0.percent < $1.percent })
    }

    private var topArtist: SpotifyArtist? {
        artists.first
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $index) {
                introCard.tag(0)
                topGenreCard.tag(1)
                topArtistCard.tag(2)
                personalityCard.tag(3)
                summaryCard.tag(4)
            }
            .tabViewStyle(PageTabViewStyle())
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.9))
                    .padding()
            }
        }
    }
}

// MARK: - Cards
private extension WrappedStoryMode {

    var introCard: some View {
        ZStack {
            LinearGradient(
                colors: [.purple, .pink, .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Text("Your RockOut Wrapped")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if let name = profile?.display_name {
                    Text(name)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                }

                Text("Swipe to see what you've really been spinning.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    var topGenreCard: some View {
        ZStack {
            LinearGradient(
                colors: [.orange, .red, .pink],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Text("Your Top Genre")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(.white)

                if let (genre, _) = topGenre {
                    let emoji = GenreStyle.emoji(for: genre)
                    let color = GenreStyle.color(for: genre)

                    Text(emoji)
                        .font(.system(size: 96))

                    Text(genre.capitalized)
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(color)
                        .shadow(color: .black.opacity(0.5), radius: 12)
                } else {
                    Text("We’re still learning your top genre.")
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 30)
        }
    }

    var topArtistCard: some View {
        ZStack {
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Text("Your Top Artist")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(.white)

                if let artist = topArtist {
                    if let url = artist.imageURL {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color.white.opacity(0.2)
                        }
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                        .shadow(color: .black.opacity(0.7), radius: 20)
                    }

                    Text(artist.name)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("We don’t have a top artist yet.")
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 30)
        }
    }

    var personalityCard: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Your Listening Personality")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.white)

                if let p = personality {
                    Text(p.emoji)
                        .font(.system(size: 90))

                    Text(p.title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(p.description)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else {
                    Text("We’re still figuring you out.")
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 30)
        }
    }

    var summaryCard: some View {
        ZStack {
            LinearGradient(
                colors: [.mint, .teal, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("That’s your SoundPrint")
                    .font(.system(size: 40, weight: .heavy))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Share it, flex it, or keep it just for you.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}
