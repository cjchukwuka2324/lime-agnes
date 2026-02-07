import Foundation
import Supabase
import UIKit

@MainActor
final class RecallActionsService: ObservableObject {
    static let shared = RecallActionsService()
    
    private let supabase = SupabaseService.shared.client
    private let feedbackService = RecallFeedbackService.shared
    
    private init() {}
    
    // MARK: - Share
    
    func share(
        title: String,
        artist: String,
        url: String?,
        recallId: UUID,
        from viewController: UIViewController
    ) async throws {
        var shareItems: [Any] = ["\(title) by \(artist)"]
        
        if let url = url, let urlObject = URL(string: url) {
            shareItems.append(urlObject)
        }
        
        let activityViewController = UIActivityViewController(
            activityItems: shareItems,
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        await MainActor.run {
            viewController.present(activityViewController, animated: true)
        }
        
        // Record implicit feedback
        try? await feedbackService.recordImplicitFeedback(
            recallId: recallId,
            action: "share",
            candidateTitle: title,
            candidateArtist: artist
        )
    }
    
    // MARK: - Post to GreenRoom
    
    func postToGreenRoom(
        title: String,
        artist: String,
        url: String?,
        confidence: Double?,
        recallId: UUID
    ) async throws {
        guard let session = supabase.auth.currentSession else {
            throw NSError(domain: "RecallActionsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallActionsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Build post content
        var postText = "🎵 Found: \(title) by \(artist)"
        if let confidence = confidence {
            let confidencePercent = Int(confidence * 100)
            postText += " (\(confidencePercent)% match)"
        }
        if let url = url {
            postText += "\n\n\(url)"
        }
        
        // Create GreenRoom post
        // Note: Adjust this based on your actual GreenRoom schema
        var metadata: [String: String] = [
            "recall_id": recallId.uuidString,
            "song_title": title,
            "song_artist": artist
        ]
        if let confidence = confidence {
            metadata["confidence"] = String(confidence)
        }
        if let url = url {
            metadata["song_url"] = url
        }
        
        struct PostBody: Encodable {
            let userId: String
            let content: String
            let type: String
            let metadata: [String: String]
            
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case content
                case type
                case metadata
            }
        }
        
        let postBody = PostBody(
            userId: userId.uuidString,
            content: postText,
            type: "recall_share",
            metadata: metadata
        )
        
        let response = try await supabase
            .from("posts") // Adjust table name as needed
            .insert(postBody)
            .execute()
        
        print("✅ RecallActionsService: Posted to GreenRoom")
        
        // Record implicit feedback
        try? await feedbackService.recordImplicitFeedback(
            recallId: recallId,
            action: "post",
            candidateTitle: title,
            candidateArtist: artist
        )
    }
    
    // MARK: - Save
    
    func save(
        recallId: UUID,
        title: String? = nil,
        artist: String? = nil
    ) async throws {
        guard let session = supabase.auth.currentSession else {
            throw NSError(domain: "RecallActionsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallActionsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Check if already saved
        let existing = try await supabase
            .from("saved_recalls")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("recall_id", value: recallId.uuidString)
            .single()
            .execute()
        
        if existing.data.count > 0 {
            // Already saved
            return
        }
        
        // Save recall
        struct SaveBody: Encodable {
            let userId: String
            let recallId: String
            
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case recallId = "recall_id"
            }
        }
        
        let saveBody = SaveBody(
            userId: userId.uuidString,
            recallId: recallId.uuidString
        )
        
        let response = try await supabase
            .from("saved_recalls")
            .insert(saveBody)
            .execute()
        
        print("✅ RecallActionsService: Saved recall")
        
        // Record implicit feedback
        if let title = title, let artist = artist {
            try? await feedbackService.recordImplicitFeedback(
                recallId: recallId,
                action: "save",
                candidateTitle: title,
                candidateArtist: artist
            )
        }
    }
    
    // MARK: - Unsave
    
    func unsave(recallId: UUID) async throws {
        guard let session = supabase.auth.currentSession else {
            throw NSError(domain: "RecallActionsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallActionsService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await supabase
            .from("saved_recalls")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .eq("recall_id", value: recallId.uuidString)
            .execute()
        
        print("✅ RecallActionsService: Unsaved recall")
    }
    
    // MARK: - Check if Saved
    
    func isSaved(recallId: UUID) async throws -> Bool {
        guard let userId = supabase.auth.currentUser?.id else {
            return false
        }
        
        let response = try await supabase
            .from("saved_recalls")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("recall_id", value: recallId.uuidString)
            .limit(1)
            .execute()
        
        return response.data.count > 0
    }
}










