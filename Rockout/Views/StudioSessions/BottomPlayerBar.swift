import SwiftUI

// Custom shape for rounded top corners only
struct TopRoundedRectangle: Shape {
    var cornerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        
        return path
    }
}

struct BottomPlayerBar: View {
    @ObservedObject var playerVM: AudioPlayerViewModel
    @State private var showFullPlayer = false
    
    var body: some View {
        if let track = playerVM.currentTrack {
            
            Button {
                showFullPlayer = true
            } label: {
                ZStack(alignment: .top) {
                    // MAIN BAR CONTENT
                    HStack(spacing: 12) {
                        
                        // --- COVER ART ---
                        albumArt
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        // --- TITLE & ALBUM ---
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            if let album = playerVM.currentAlbum {
                                Text(album.title)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // --- PLAYBACK CONTROLS ---
                        HStack(spacing: 16) {
                            
                            // previous track
                            Button {
                                playerVM.previousTrack()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                            }
                            
                            // play/pause
                            Button {
                                if playerVM.isPlaying {
                                    playerVM.pause()
                                } else {
                                    playerVM.play()
                                }
                            } label: {
                                Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 24, weight: .bold))
                            }
                            
                            // next track
                            Button {
                                playerVM.nextTrack()
                            } label: {
                                Image(systemName: "forward.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Color.black
                            .frame(minHeight: 0)
                    )
                    .clipShape(TopRoundedRectangle(cornerRadius: 12))
                    .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: -4)
                    
                    // --- PROGRESS BAR (SCRUBBABLE) AT TOP ---
                    if playerVM.duration > 0 {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track
                                Rectangle()
                                    .fill(Color.white.opacity(0.25))
                                    .frame(height: 2)
                                
                                // Progress fill
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(
                                        width: progressWidth(geometry: geometry),
                                        height: 2
                                    )
                                
                                // Draggable thumb (circular scrubber button)
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 12, height: 12)
                                    .offset(x: progressWidth(geometry: geometry) - 6)
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                let newTime = Double(value.location.x / geometry.size.width) * playerVM.duration
                                                playerVM.seek(to: max(0, min(newTime, playerVM.duration)))
                                            }
                                    )
                            }
                            .frame(height: 44) // Touch area for the scrubber
                        }
                        .frame(height: 44)
                    }
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFullPlayer) {
                if let track = playerVM.currentTrack {
                    AudioPlayerView(track: track)
                }
            }
        }
    }
    
    
    // MARK: - Album Art Loader
    
    private var albumArt: some View {
        Group {
            if let album = playerVM.currentAlbum,
               let urlString = album.cover_art_url,
               let url = URL(string: urlString) {
                
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
    }
    
    
    // MARK: - Progress Width Helper
    
    private func progressWidth(geometry: GeometryProxy) -> CGFloat {
        guard playerVM.duration > 0, playerVM.duration.isFinite else { return 0 }
        let progress = playerVM.currentTime / playerVM.duration
        return min(geometry.size.width * CGFloat(progress), geometry.size.width)
    }
    
    // MARK: - Placeholder Artwork
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.2, blue: 0.3),
                            Color(red: 0.1, green: 0.1, blue: 0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .foregroundColor(.white.opacity(0.3))
                .font(.system(size: 20))
        }
    }
}
