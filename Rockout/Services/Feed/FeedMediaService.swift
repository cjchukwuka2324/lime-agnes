import Foundation
import Supabase
import UIKit
import AVFoundation

@MainActor
class FeedMediaService {
    static let shared = FeedMediaService()
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    // MARK: - Upload Video
    
    func uploadPostVideo(_ videoURL: URL) async throws -> URL {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "FeedMediaService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Read video data
        let videoData = try Data(contentsOf: videoURL)
        
        let filename = "\(UUID().uuidString).mp4"
        let path = "feed_posts/\(userId.uuidString)/videos/\(filename)"
        
        try await supabase.storage
            .from("feed-images")
            .upload(path: path, file: videoData)
        
        let publicURL = try supabase.storage
            .from("feed-images")
            .getPublicURL(path: path)
        
        return publicURL
    }
    
    // MARK: - Upload Audio
    
    func uploadPostAudio(_ audioURL: URL) async throws -> URL {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "FeedMediaService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Read audio data
        let audioData = try Data(contentsOf: audioURL)
        
        let filename = "\(UUID().uuidString).m4a"
        let path = "feed_posts/\(userId.uuidString)/audio/\(filename)"
        
        try await supabase.storage
            .from("feed-images")
            .upload(path: path, file: audioData)
        
        let publicURL = try supabase.storage
            .from("feed-images")
            .getPublicURL(path: path)
        
        return publicURL
    }
}


