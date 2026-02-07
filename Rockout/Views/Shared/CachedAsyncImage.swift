import SwiftUI
import UIKit

/// A SwiftUI view that loads images using ImageCache for efficient memory management.
/// This is a drop-in replacement for AsyncImage that provides:
/// - LRU cache eviction (max 100MB or 500 images)
/// - Automatic memory management
/// - Consistent caching across the app
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = loadedImage {
                content(Image(uiImage: image))
            } else if isLoading {
                placeholder()
            } else {
                placeholder() // Show placeholder on error
            }
        }
        .task {
            guard let url = url else {
                isLoading = false
                return
            }
            
            // Load from cache
            let cachedImage = await ImageCache.shared.image(for: url)
            if let cachedImage = cachedImage {
                loadedImage = cachedImage
                isLoading = false
            } else {
                // Image not in cache or failed to load
                isLoading = false
            }
        }
    }
}

/// Simplified version that matches AsyncImage API more closely
struct CachedImage: View {
    let url: URL?
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else {
                ProgressView()
            }
        }
        .task {
            guard let url = url else { return }
            image = await ImageCache.shared.image(for: url)
        }
    }
}

