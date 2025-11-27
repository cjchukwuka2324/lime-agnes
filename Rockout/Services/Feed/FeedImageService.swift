import Foundation
import Supabase
import UIKit

@MainActor
class FeedImageService {
    static let shared = FeedImageService()
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    func uploadPostImage(_ image: UIImage) async throws -> URL {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "FeedImageService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "FeedImageService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
        }
        
        let filename = "\(UUID().uuidString).jpg"
        let path = "feed_posts/\(userId.uuidString)/\(filename)"
        
        try await supabase.storage
            .from("feed-images")
            .upload(path: path, file: imageData)
        
        let publicURL = try supabase.storage
            .from("feed-images")
            .getPublicURL(path: path)
        
        return publicURL
    }
}

