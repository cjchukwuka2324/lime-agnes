import SwiftUI

struct SoundPrintExportCard: View {

    let profile: SpotifyUserProfile?
    let profileImage: UIImage?
    let artists: [SpotifyArtist]
    let artistImages: [String: UIImage]
    let tracks: [SpotifyTrack]
    let albumImages: [String: UIImage]
    let genres: [GenreStat]
    let personality: FanPersonality?

    // Export canvas – matches ShareExporter width: 1080
    private let cardWidth: CGFloat = 1080
    private let cardHeight: CGFloat = 1920

    var body: some View {
        ZStack {
            background

            VStack(spacing: 60) {

                // MARK: - PROFILE
                profileSection

                // MARK: - GENRES
                if !genres.isEmpty {
                    genresSection
                }

                // MARK: - ARTISTS
                if !artists.isEmpty {
                    artistsSection
                }

                // MARK: - TRACKS
                if !tracks.isEmpty {
                    tracksSection
                }

                // MARK: - PERSONALITY
                if let p = personality {
                    personalitySection(p)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 80)
            .padding(.top, 80)
            .padding(.bottom, 60)
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

// MARK: - Background

private extension SoundPrintExportCard {
    var background: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.06, green: 0.06, blue: 0.14),
                Color(red: 0.10, green: 0.10, blue: 0.20)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Sections

private extension SoundPrintExportCard {

    // PROFILE

    var profileSection: some View {
        VStack(spacing: 24) {

            // avatar
            Group {
                if let img = profileImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else if let url = profile?.imageURL {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.white.opacity(0.2)
                    }
                } else {
                    Color.white.opacity(0.2)
                }
            }
            .frame(width: 230, height: 230)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.yellow, lineWidth: 10))
            .shadow(color: .yellow.opacity(0.5), radius: 30)

            Text(profile?.display_name ?? "Your SoundPrint")
                .font(.system(size: 80, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            if let top = genres.first {
                Text("Top Genre • \(top.genre.capitalized)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.yellow)
            }
        }
    }

    // GENRES

    var genresSection: some View {
        VStack(spacing: 24) {
            Text("Top Genres")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            FlowLayout(
                mode: .vstack,
                items: Array(genres.prefix(12)),
                itemSpacing: 16,
                rowSpacing: 16
            ) { stat in
                Text("\(stat.genre.capitalized) • \(Int(stat.percent * 100))%")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 18)
                    .background(Color.yellow)
                    .clipShape(Capsule())
                    .shadow(color: Color.yellow.opacity(0.35), radius: 6, y: 2)
            }
        }
    }

    // ARTISTS

    var artistsSection: some View {
        VStack(spacing: 24) {
            Text("Top Artists")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            HStack(spacing: 28) {
                ForEach(artists.prefix(4)) { artist in
                    VStack(spacing: 10) {
                        if let img = artistImages[artist.id] {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 170, height: 170)
                                .clipShape(RoundedRectangle(cornerRadius: 26))
                                .shadow(radius: 12)
                        } else if let url = artist.imageURL {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color.white.opacity(0.2)
                            }
                            .frame(width: 170, height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                        } else {
                            RoundedRectangle(cornerRadius: 26)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 170, height: 170)
                        }

                        Text(artist.name)
                            .font(.system(size: 26, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // TRACKS

    var tracksSection: some View {
        VStack(spacing: 20) {
            Text("Top Tracks")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            VStack(spacing: 14) {
                ForEach(tracks.prefix(6)) { track in
                    HStack(spacing: 14) {

                        // album art
                        if let img = albumImages[track.id] {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else if let album = track.album as SpotifyAlbum?,
                                  let url = album.imageURL {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color.white.opacity(0.2)
                            }
                            .frame(width: 90, height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 90, height: 90)
                        }

                        Text(track.name)
                            .font(.system(size: 30, weight: .regular, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()
                    }
                }
            }
        }
    }

    // PERSONALITY

    func personalitySection(_ p: FanPersonality) -> some View {
        VStack(spacing: 22) {
            Text("Personality")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(p.emoji)
                .font(.system(size: 140))

            Text(p.title)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(p.description)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
        }
    }
}
