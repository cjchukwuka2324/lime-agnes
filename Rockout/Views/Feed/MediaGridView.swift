import SwiftUI

/// Twitter-style grid layout for displaying multiple images/videos in a post
struct MediaGridView: View {
    let imageURLs: [URL]
    let videoURL: URL?
    let onTap: () -> Void
    
    private var mediaCount: Int {
        imageURLs.count + (videoURL != nil ? 1 : 0)
    }
    
    var body: some View {
        Group {
            switch mediaCount {
            case 0:
                EmptyView()
            case 1:
                singleMediaView
            case 2:
                twoMediaGrid
            case 3:
                threeMediaGrid
            case 4:
                fourMediaGrid
            default:
                fivePlusMediaGrid
            }
        }
    }
    
    // MARK: - Single Media
    
    private var singleMediaView: some View {
        Group {
            if let videoURL = videoURL {
                VideoThumbnailView(videoURL: videoURL, onTap: onTap)
            } else if let firstImage = imageURLs.first {
                ImageThumbnailView(imageURL: firstImage, onTap: onTap)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16/9, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Two Media Grid
    
    private var twoMediaGrid: some View {
        HStack(spacing: 2) {
            if let videoURL = videoURL {
                VideoThumbnailView(videoURL: videoURL, onTap: onTap)
            } else if let firstImage = imageURLs.first {
                ImageThumbnailView(imageURL: firstImage, onTap: onTap)
            }
            
            if imageURLs.count > 1 {
                ImageThumbnailView(imageURL: imageURLs[1], onTap: onTap)
            } else if videoURL != nil && imageURLs.count > 0 {
                ImageThumbnailView(imageURL: imageURLs[0], onTap: onTap)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Three Media Grid
    
    private var threeMediaGrid: some View {
        HStack(spacing: 2) {
            // Large image on left (50%)
            if let firstImage = imageURLs.first {
                ImageThumbnailView(imageURL: firstImage, onTap: onTap)
                    .frame(width: UIScreen.main.bounds.width * 0.5 - 1)
            } else if let videoURL = videoURL {
                VideoThumbnailView(videoURL: videoURL, onTap: onTap)
                    .frame(width: UIScreen.main.bounds.width * 0.5 - 1)
            }
            
            // Two stacked on right (25% each)
            VStack(spacing: 2) {
                if imageURLs.count > 1 {
                    ImageThumbnailView(imageURL: imageURLs[1], onTap: onTap)
                } else if videoURL != nil {
                    VideoThumbnailView(videoURL: videoURL!, onTap: onTap)
                }
                
                if imageURLs.count > 2 {
                    ImageThumbnailView(imageURL: imageURLs[2], onTap: onTap)
                } else if videoURL != nil && imageURLs.count > 0 {
                    ImageThumbnailView(imageURL: imageURLs[0], onTap: onTap)
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.5 - 1)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Four Media Grid
    
    private var fourMediaGrid: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                if imageURLs.count > 0 {
                    ImageThumbnailView(imageURL: imageURLs[0], onTap: onTap)
                } else if let videoURL = videoURL {
                    VideoThumbnailView(videoURL: videoURL, onTap: onTap)
                }
                
                if imageURLs.count > 1 {
                    ImageThumbnailView(imageURL: imageURLs[1], onTap: onTap)
                }
            }
            
            HStack(spacing: 2) {
                if imageURLs.count > 2 {
                    ImageThumbnailView(imageURL: imageURLs[2], onTap: onTap)
                }
                
                if imageURLs.count > 3 {
                    ImageThumbnailView(imageURL: imageURLs[3], onTap: onTap)
                } else if videoURL != nil {
                    VideoThumbnailView(videoURL: videoURL!, onTap: onTap)
                }
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Five+ Media Grid
    
    private var fivePlusMediaGrid: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                if imageURLs.count > 0 {
                    ImageThumbnailView(imageURL: imageURLs[0], onTap: onTap)
                } else if let videoURL = videoURL {
                    VideoThumbnailView(videoURL: videoURL, onTap: onTap)
                }
                
                if imageURLs.count > 1 {
                    ImageThumbnailView(imageURL: imageURLs[1], onTap: onTap)
                }
            }
            
            HStack(spacing: 2) {
                if imageURLs.count > 2 {
                    ImageThumbnailView(imageURL: imageURLs[2], onTap: onTap)
                }
                
                // Last cell with "+N" overlay
                ZStack {
                    if imageURLs.count > 3 {
                        ImageThumbnailView(imageURL: imageURLs[3], onTap: onTap)
                    } else if videoURL != nil {
                        VideoThumbnailView(videoURL: videoURL!, onTap: onTap)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

