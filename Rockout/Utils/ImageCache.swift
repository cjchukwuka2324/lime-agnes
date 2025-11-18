import UIKit

actor ImageCache {
    static let shared = ImageCache()
    private var store: [URL: UIImage] = [:]

    func image(for url: URL) async -> UIImage? {
        if let cached = store[url] { return cached }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let img = UIImage(data: data)
            if let img = img {
                store[url] = img
            }
            return img
        } catch {
            return nil
        }
    }
}
