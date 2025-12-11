import SwiftUI
import UIKit

struct SocialSharingView: View {
    let profile: UnifiedUserProfile?
    let topArtists: [UnifiedArtist]
    let topTracks: [UnifiedTrack]
    let personality: FanPersonality?
    let compatibility: [TasteCompatibility]?
    let genreStats: [GenreStat]
    let listeningStats: ListeningStats?
    let audioFeatures: AverageAudioFeatures?
    
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var isGeneratingImage = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Share SoundPrint Card
                ShareSoundPrintCard(
                    profile: profile,
                    personality: personality,
                    onShare: {
                        Task {
                            await generateShareImage()
                            if shareImage != nil {
                                showShareSheet = true
                            }
                        }
                    },
                    isGenerating: isGeneratingImage
                )
                
                // Taste Compatibility
                if let compat = compatibility, !compat.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Taste Compatibility")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        ForEach(compat, id: \.userId) { comp in
                            CompatibilityRow(compatibility: comp)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(activityItems: [image])
            }
        }
    }
    
    // MARK: - Generate Story Image (final version)
    @MainActor
    private func generateShareImage() async {
        isGeneratingImage = true
        defer { isGeneratingImage = false }

        // Preload images
        let preloaded = await preloadImages(
            artists: Array(topArtists.prefix(10)),
            tracks: Array(topTracks.prefix(10))
        )

        // 1️⃣ Render SoundPrint card at natural size
        let cardView = SoundPrintShareCardView(
            profile: profile,
            personality: personality,
            topArtists: Array(topArtists.prefix(10)),
            topTracks: Array(topTracks.prefix(10)),
            genreStats: Array(genreStats.prefix(10)),
            listeningStats: listeningStats,
            audioFeatures: audioFeatures,
            preloadedImages: preloaded
        )

        guard let baseImage = await ShareExporter.renderImage(cardView, width: 1080, scale: 3.0) else {
            return
        }

        let targetWidth: CGFloat = 1080
        let targetHeight: CGFloat = 1920

        // 2️⃣ Compute scale factor that FITS inside 9:16
        let scale = min(
            targetWidth / baseImage.size.width,
            targetHeight / baseImage.size.height
        )

        let scaledWidth = baseImage.size.width * scale
        let scaledHeight = baseImage.size.height * scale

        // 3️⃣ Draw into full Instagram Story canvas
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetWidth, height: targetHeight))
        let finalImage = renderer.image { ctx in

            // Background gradient
            let colors = [
                UIColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1),
                UIColor(red: 0.10, green: 0.10, blue: 0.15, alpha: 1)
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map { $0.cgColor } as CFArray,
                locations: [0, 1]
            )!

            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: targetWidth, y: targetHeight),
                options: []
            )

            // 4️⃣ Center and draw scaled content
            let originX = (targetWidth - scaledWidth) / 2
            let originY = (targetHeight - scaledHeight) / 2

            baseImage.draw(
                in: CGRect(
                    x: originX,
                    y: originY,
                    width: scaledWidth,
                    height: scaledHeight
                )
            )
        }

        // 5️⃣ Store the final poster
        self.shareImage = finalImage
    }

    
    // MARK: - Image Preloading
    
    private func preloadImages(artists: [UnifiedArtist], tracks: [UnifiedTrack]) async -> [String: UIImage] {
        var images: [String: UIImage] = [:]
        
        // Preload artist images
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for artist in artists {
                if let imageURL = artist.imageURL {
                    group.addTask {
                        if let url = URL(string: imageURL),
                           let (data, _) = try? await URLSession.shared.data(from: url),
                           let image = UIImage(data: data) {
                            return (imageURL, image)
                        }
                        return (imageURL, nil)
                    }
                }
            }
            
            for await (urlString, image) in group {
                if let image = image {
                    images[urlString] = image
                }
            }
        }
        
        // Preload track album artwork
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for track in tracks {
                if let album = track.album,
                   let imageURL = album.imageURL {
                    group.addTask {
                        if let url = URL(string: imageURL),
                           let (data, _) = try? await URLSession.shared.data(from: url),
                           let image = UIImage(data: data) {
                            return (imageURL, image)
                        }
                        return (imageURL, nil)
                    }
                }
            }
            
            for await (urlString, image) in group {
                if let image = image {
                    images[urlString] = image
                }
            }
        }
        
        return images
    }
}

struct ShareSoundPrintCard: View {
    let profile: UnifiedUserProfile?
    let personality: FanPersonality?
    let onShare: () -> Void
    let isGenerating: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Share Your SoundPrint")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text("Show off your musical identity")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            Button {
                onShare()
            } label: {
                HStack(spacing: 12) {
                    if isGenerating {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isGenerating ? "Generating..." : "Share SoundPrint")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(16)
            }
            .disabled(isGenerating)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

// MARK: - Shareable SoundPrint Card View

struct SoundPrintShareCardView: View {
    let profile: UnifiedUserProfile?
    let personality: FanPersonality?
    let topArtists: [UnifiedArtist]
    let topTracks: [UnifiedTrack]
    let genreStats: [GenreStat]
    let listeningStats: ListeningStats?
    let audioFeatures: AverageAudioFeatures?
    let preloadedImages: [String: UIImage]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.1, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 10) {
                // Header
                VStack(spacing: 6) {
                    Text("🎵")
                        .font(.system(size: 32))
                    
                    Text("My SoundPrint")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    if let profile = profile, let displayName = profile.displayName {
                        Text(displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    if let personality = personality {
                        Text(personality.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.12, green: 0.72, blue: 0.33).opacity(0.2))
                            )
                    }
                }
                .padding(.top, 18)
                .padding(.bottom, 6)
                
                // Two column layout for artists and tracks
                HStack(alignment: .top, spacing: 16) {
                    // Left column - Top Artists
                    if !topArtists.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Top Artists")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.bottom, 2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(topArtists.enumerated()), id: \.element.id) { index, artist in
                                    HStack(spacing: 5) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                                            .frame(width: 16)
                                        
                                        // Artist Image
                                        Group {
                                            if let imageURL = artist.imageURL,
                                               let image = preloadedImages[imageURL] {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                            } else {
                                                artistImagePlaceholder
                                            }
                                        }
                                        .frame(width: 30, height: 30)
                                        .clipShape(Circle())
                                        
                                        Text(artist.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Right column - Top Tracks
                    if !topTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Top Tracks")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.bottom, 2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(topTracks.enumerated()), id: \.element.id) { index, track in
                                    HStack(spacing: 5) {
                                        Text("\(index + 1)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                                            .frame(width: 16)
                                        
                                        // Track Album Artwork
                                        Group {
                                            if let album = track.album,
                                               let imageURL = album.imageURL,
                                               let image = preloadedImages[imageURL] {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                            } else {
                                                trackImagePlaceholder
                                            }
                                        }
                                        .frame(width: 30, height: 30)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                        
                                        Text(track.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 6)
                
                // Genres
                if !genreStats.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Top Genres")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(genreStats.enumerated()), id: \.element.genre) { index, genre in
                                HStack(spacing: 5) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                                        .frame(width: 16)
                                    
                                    Text(genre.genre.capitalized)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Text("\(Int(genre.percent * 100))%")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 6)
                }
                
                // Analytics
                if let stats = listeningStats, let features = audioFeatures {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Analytics")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 2)
                        
                        VStack(spacing: 3) {
                            HStack {
                                Text("Listening Time")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text(formatTime(stats.totalListeningTimeMinutes))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            HStack {
                                Text("Tracks Played")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(stats.totalSongsPlayed)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            HStack {
                                Text("Artists")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(stats.totalArtistsListened)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            HStack {
                                Text("Energy")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(features.energy * 100))%")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            HStack {
                                Text("Danceability")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Text("\(Int(features.danceability * 100))%")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 6)
                }
                
                Spacer(minLength: 0)
                
                // Footer
                Text("Check out my SoundPrint on Rockout!")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 20)
            }
        }
        .frame(width: 1080)                       // fixed width only
        .background(Color.black)                  // ensures clean backdrop
        .clipped()                                // avoids overflow if any
    }
    
    private func formatTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }
    
    // MARK: - Image Placeholders
    
    private var artistImagePlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
            
            Image(systemName: "music.mic")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    private var trackImagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.1))
            
            Image(systemName: "music.note")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

struct CompatibilityRow: View {
    let compatibility: TasteCompatibility
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(compatibility.userName)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(Int(compatibility.compatibilityScore))% match")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Compatibility score visual
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 6)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: CGFloat(compatibility.compatibilityScore / 100))
                    .stroke(Color(red: 0.12, green: 0.72, blue: 0.33), lineWidth: 6)
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(compatibility.compatibilityScore))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 12)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
