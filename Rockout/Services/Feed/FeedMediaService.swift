import Foundation
import Supabase
import UIKit
import AVFoundation

@MainActor
class FeedMediaService {
    static let shared = FeedMediaService()
    
    private let supabase = SupabaseService.shared.client
    private let maxVideoSizeBytes: Int64 = 10 * 1024 * 1024 // 10MB limit
    
    private init() {}
    
    // MARK: - Upload Video
    
    func uploadPostVideo(_ videoURL: URL) async throws -> URL {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "FeedMediaService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("📹 FeedMediaService: Starting video upload")
        print("📹 Video file: \(videoURL.lastPathComponent)")
        
        // Check original file size
        let originalFileSize: Int64
        if let attributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path) {
            if let size = attributes[.size] as? Int64 {
                originalFileSize = size
                print("📹 Original video file size: \(originalFileSize) bytes (\(originalFileSize / 1024 / 1024)MB)")
            } else {
                originalFileSize = 0
            }
        } else {
            originalFileSize = 0
        }
        
        // Compress video if needed
        let processedVideoURL: URL
        if originalFileSize > maxVideoSizeBytes {
            print("📹 Video exceeds size limit, compressing...")
            processedVideoURL = try await compressVideo(videoURL)
            
            if let attributes = try? FileManager.default.attributesOfItem(atPath: processedVideoURL.path),
               let compressedSize = attributes[.size] as? Int64 {
                print("📹 Compressed video size: \(compressedSize) bytes (\(compressedSize / 1024 / 1024)MB)")
            }
        } else {
            processedVideoURL = videoURL
        }
        
        // Read video data
        let videoData: Data
        do {
            videoData = try Data(contentsOf: processedVideoURL)
            print("📹 Video data loaded: \(videoData.count) bytes")
        } catch {
            print("❌ Failed to read video data: \(error.localizedDescription)")
            throw NSError(domain: "FeedMediaService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to read video file: \(error.localizedDescription)"])
        }
        
        // Check if still too large after compression
        if Int64(videoData.count) > maxVideoSizeBytes {
            // Clean up compressed file if we created it
            if processedVideoURL != videoURL {
                try? FileManager.default.removeItem(at: processedVideoURL)
            }
            throw NSError(domain: "FeedMediaService", code: 413, userInfo: [NSLocalizedDescriptionKey: "Video is too large even after compression. Maximum size is 10MB."])
        }
        
        let filename = "\(UUID().uuidString).mp4"
        let path = "feed_posts/\(userId.uuidString)/videos/\(filename)"
        print("📹 Uploading to path: \(path)")
        
        defer {
            // Clean up compressed file if we created it
            if processedVideoURL != videoURL {
                try? FileManager.default.removeItem(at: processedVideoURL)
            }
        }
        
        do {
            try await supabase.storage
                .from("feed-images")
                .upload(path: path, file: videoData)
            print("✅ Video uploaded to storage")
        } catch {
            print("❌ Storage upload failed: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            throw error
        }
        
        let publicURL: URL
        do {
            publicURL = try supabase.storage
                .from("feed-images")
                .getPublicURL(path: path)
            print("✅ Public URL generated: \(publicURL.absoluteString)")
        } catch {
            print("❌ Failed to get public URL: \(error.localizedDescription)")
            throw error
        }
        
        return publicURL
    }
    
    // MARK: - Video Compression
    
    private func compressVideo(_ inputURL: URL) async throws -> URL {
        print("📹 Starting video compression...")
        let asset = AVAsset(url: inputURL)
        
        // Create export session with medium quality preset (good balance of size/quality)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            throw NSError(domain: "FeedMediaService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true // Optimize for streaming/upload
        
        // Export video
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
            print("❌ Video compression failed: \(errorMessage)")
            if let error = exportSession.error {
                throw error
            }
            throw NSError(domain: "FeedMediaService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Video export failed: \(errorMessage)"])
        }
        
        print("✅ Video compression completed")
        return outputURL
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


