import SwiftUI

/// Twitter-style grid layout for displaying multiple images/videos in a post
struct MediaGridView: View {
    let imageURLs: [URL]
    let videoURL: URL?
    let onTap: (Int) -> Void
    
    private var mediaCount: Int {
        imageURLs.count + (videoURL != nil ? 1 : 0)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            
            Group {
                switch mediaCount {
                case 0:
                    EmptyView()
                case 1:
                    singleMediaView
                case 2:
                    twoMediaGrid(availableWidth: availableWidth)
                case 3:
                    threeMediaGrid(availableWidth: availableWidth)
                case 4:
                    fourMediaGrid(availableWidth: availableWidth)
                default:
                    fivePlusMediaGrid(availableWidth: availableWidth)
                }
            }
            .frame(width: availableWidth, height: calculateHeight())
        }
        .frame(height: calculateHeight())
        .clipped()
    }
    
    private func calculateHeight() -> CGFloat {
        switch mediaCount {
        case 0: return 0
        case 1: return 200
        case 2, 3, 4: return 200
        default: return 200
        }
    }
    
    // MARK: - Single Media
    
    private var singleMediaView: some View {
        Group {
            if let videoURL = videoURL {
                VideoThumbnailView(videoURL: videoURL, onTap: { onTap(0) })
            } else if let firstImage = imageURLs.first {
                ImageThumbnailView(imageURL: firstImage, onTap: { onTap(0) })
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16/9, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Two Media Grid
    
    private func twoMediaGrid(availableWidth: CGFloat) -> some View {
        HStack(spacing: 2) {
            if let videoURL = videoURL {
                VideoThumbnailView(videoURL: videoURL, onTap: { onTap(0) })
            } else if let firstImage = imageURLs.first {
                ImageThumbnailView(imageURL: firstImage, onTap: { onTap(0) })
            }
            
            if imageURLs.count > 1 {
                ImageThumbnailView(imageURL: imageURLs[1], onTap: { onTap(1) })
            } else if videoURL != nil && imageURLs.count > 0 {
                ImageThumbnailView(imageURL: imageURLs[0], onTap: { onTap(0) })
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Three Media Grid
    
    private func threeMediaGrid(availableWidth: CGFloat) -> some View {
        HStack(spacing: 2) {
            // Large image on left (50%)
            let leftWidth = (availableWidth - 2) * 0.5
            if let firstImage = imageURLs.first {
                ImageThumbnailView(imageURL: firstImage, onTap: { onTap(0) })
                    .frame(width: leftWidth)
            } else if let videoURL = videoURL {
                VideoThumbnailView(videoURL: videoURL, onTap: { onTap(0) })
                    .frame(width: leftWidth)
            }
            
            // Two stacked on right (25% each)
            let rightWidth = (availableWidth - 2) * 0.5
            VStack(spacing: 2) {
                if imageURLs.count > 1 {
                    ImageThumbnailView(imageURL: imageURLs[1], onTap: { onTap(1) })
                } else if videoURL != nil {
                    VideoThumbnailView(videoURL: videoURL!, onTap: { onTap(0) })
                }
                
                if imageURLs.count > 2 {
                    ImageThumbnailView(imageURL: imageURLs[2], onTap: { onTap(2) })
                } else if videoURL != nil && imageURLs.count > 0 {
                    ImageThumbnailView(imageURL: imageURLs[0], onTap: { onTap(0) })
                }
            }
            .frame(width: rightWidth)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Four Media Grid
    
    private func fourMediaGrid(availableWidth: CGFloat) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                if imageURLs.count > 0 {
                    ImageThumbnailView(imageURL: imageURLs[0], onTap: { onTap(0) })
                } else if let videoURL = videoURL {
                    VideoThumbnailView(videoURL: videoURL, onTap: { onTap(0) })
                }
                
                if imageURLs.count > 1 {
                    ImageThumbnailView(imageURL: imageURLs[1], onTap: { onTap(1) })
                }
            }
            
            HStack(spacing: 2) {
                if imageURLs.count > 2 {
                    ImageThumbnailView(imageURL: imageURLs[2], onTap: { onTap(2) })
                }
                
                if imageURLs.count > 3 {
                    ImageThumbnailView(imageURL: imageURLs[3], onTap: { onTap(3) })
                } else if videoURL != nil {
                    VideoThumbnailView(videoURL: videoURL!, onTap: { onTap(0) })
                }
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Five+ Media Grid
    
    private func fivePlusMediaGrid(availableWidth: CGFloat) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                if imageURLs.count > 0 {
                    ImageThumbnailView(imageURL: imageURLs[0], onTap: { onTap(0) })
                } else if let videoURL = videoURL {
                    VideoThumbnailView(videoURL: videoURL, onTap: { onTap(0) })
                }
                
                if imageURLs.count > 1 {
                    ImageThumbnailView(imageURL: imageURLs[1], onTap: { onTap(1) })
                }
            }
            
            HStack(spacing: 2) {
                if imageURLs.count > 2 {
                    ImageThumbnailView(imageURL: imageURLs[2], onTap: { onTap(2) })
                }
                
                // Last cell with "+N" overlay
                ZStack {
                    if imageURLs.count > 3 {
                        ImageThumbnailView(imageURL: imageURLs[3], onTap: { onTap(3) })
                    } else if videoURL != nil {
                        VideoThumbnailView(videoURL: videoURL!, onTap: { onTap(0) })
                    }
                    
                    // Overlay showing remaining count
                    if mediaCount > 4 {
                        Color.black.opacity(0.5)
                            .overlay(
                                Text("+\(mediaCount - 4)")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Image Thumbnail View

private struct ImageThumbnailView: View {
    let imageURL: URL
    let onTap: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.1))
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                        .clipped()
                case .failure:
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.1))
                @unknown default:
                    EmptyView()
                }
            }
        }
        .aspectRatio(contentMode: .fill)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Video Thumbnail View

private struct VideoThumbnailView: View {
    let videoURL: URL
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            // Video thumbnail placeholder
            Color.white.opacity(0.1)
            
            // Play button overlay
            Image(systemName: "play.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

