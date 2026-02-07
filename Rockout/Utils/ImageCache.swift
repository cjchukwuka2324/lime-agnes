import UIKit

/// ImageCache with LRU eviction to prevent memory leaks.
/// Maximum size: 100MB or 500 images, whichever is reached first.
actor ImageCache {
    static let shared = ImageCache()
    
    private struct CachedImage {
        let image: UIImage
        let size: Int // Size in bytes
        let lastAccessed: Date
    }
    
    private var store: [URL: CachedImage] = [:]
    private var accessOrder: [URL] = [] // LRU order (most recent at end)
    
    private let maxImages = 500
    private let maxSizeBytes = 100 * 1024 * 1024 // 100MB
    private var currentSizeBytes = 0
    
    private init() {}
    
    func image(for url: URL) async -> UIImage? {
        // Check cache first
        if let cached = store[url] {
            // Update access order (move to end)
            await updateAccessOrder(url: url)
            return cached.image
        }
        
        // Fetch from network
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let img = UIImage(data: data) else {
                return nil
            }
            
            // Calculate size (approximate)
            let imageSize = data.count
            
            // Evict if necessary before adding
            await evictIfNeeded(newImageSize: imageSize)
            
            // Add to cache
            store[url] = CachedImage(image: img, size: imageSize, lastAccessed: Date())
            accessOrder.append(url)
            currentSizeBytes += imageSize
            
            return img
        } catch {
            return nil
        }
    }
    
    /// Update access order for LRU tracking
    private func updateAccessOrder(url: URL) {
        // Remove from current position
        accessOrder.removeAll { $0 == url }
        // Add to end (most recently used)
        accessOrder.append(url)
        
        // Update last accessed time
        if var cached = store[url] {
            store[url] = CachedImage(
                image: cached.image,
                size: cached.size,
                lastAccessed: Date()
            )
        }
    }
    
    /// Evict least recently used images if cache is full
    private func evictIfNeeded(newImageSize: Int) {
        // Check if we need to evict based on count
        while accessOrder.count >= maxImages && !accessOrder.isEmpty {
            evictLRU()
        }
        
        // Check if we need to evict based on size
        while (currentSizeBytes + newImageSize) > maxSizeBytes && !accessOrder.isEmpty {
            evictLRU()
        }
    }
    
    /// Evict the least recently used image
    private func evictLRU() {
        guard let lruUrl = accessOrder.first else { return }
        
        if let cached = store[lruUrl] {
            currentSizeBytes -= cached.size
        }
        
        store.removeValue(forKey: lruUrl)
        accessOrder.removeFirst()
    }
    
    /// Clear all cached images
    func clear() {
        store.removeAll()
        accessOrder.removeAll()
        currentSizeBytes = 0
    }
    
    /// Get cache statistics (for debugging)
    func stats() -> (count: Int, sizeMB: Double, oldestAccess: Date?) {
        let sizeMB = Double(currentSizeBytes) / (1024 * 1024)
        let oldestAccess = accessOrder.first.flatMap { store[$0]?.lastAccessed }
        return (count: store.count, sizeMB: sizeMB, oldestAccess: oldestAccess)
    }
}
