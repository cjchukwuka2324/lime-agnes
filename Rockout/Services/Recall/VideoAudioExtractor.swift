import Foundation
import AVFoundation
import Combine

@MainActor
final class VideoAudioExtractor: ObservableObject {
    @Published var isExtracting = false
    @Published var errorMessage: String?
    
    func extractAudio(from videoURL: URL) async throws -> URL {
        isExtracting = true
        defer { isExtracting = false }
        
        let asset = AVAsset(url: videoURL)
        
        // Check if asset is readable
        guard try await asset.load(.isReadable) else {
            throw NSError(
                domain: "VideoAudioExtractor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Video file is not readable"]
            )
        }
        
        // Create export session
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw NSError(
                domain: "VideoAudioExtractor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"]
            )
        }
        
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        // Export audio
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            let error = exportSession.error ?? NSError(
                domain: "VideoAudioExtractor",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Export failed with status: \(exportSession.status.rawValue)"]
            )
            throw error
        }
        
        return outputURL
    }
}

