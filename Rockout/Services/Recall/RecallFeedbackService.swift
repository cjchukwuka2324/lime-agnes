import Foundation
import Supabase

@MainActor
final class RecallFeedbackService: ObservableObject {
    static let shared = RecallFeedbackService()
    
    private let supabase = SupabaseService.shared.client
    
    private init() {}
    
    // MARK: - Feedback Types
    
    enum FeedbackType: String {
        case confirm = "confirm"
        case reject = "reject"
        case correct = "correct"
        case rate = "rate"
    }
    
    // MARK: - Submit Feedback
    
    func submitFeedback(
        recallId: UUID,
        messageId: UUID? = nil,
        feedbackType: FeedbackType,
        rating: Int? = nil,
        correctionText: String? = nil,
        context: [String: Any]? = nil
    ) async throws {
        guard let session = supabase.auth.currentSession else {
            throw NSError(domain: "RecallFeedbackService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "RecallFeedbackService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        var body: [String: Any] = [
            "recall_id": recallId.uuidString,
            "user_id": userId.uuidString,
            "feedback_type": feedbackType.rawValue
        ]
        
        if let messageId = messageId {
            body["message_id"] = messageId.uuidString
        }
        
        if let rating = rating {
            body["rating"] = rating
        }
        
        if let correctionText = correctionText {
            body["correction_text"] = correctionText
        }
        
        if let context = context {
            body["context_json"] = context
        }
        
        let response = try await supabase
            .from("recall_feedback")
            .insert(body)
            .execute()
        
        print("✅ RecallFeedbackService: Feedback submitted - \(feedbackType.rawValue)")
    }
    
    // MARK: - Confirm Candidate
    
    func confirmCandidate(
        recallId: UUID,
        candidateTitle: String,
        candidateArtist: String,
        messageId: UUID? = nil
    ) async throws {
        let context: [String: Any] = [
            "candidate_title": candidateTitle,
            "candidate_artist": candidateArtist,
            "action": "confirmed"
        ]
        
        try await submitFeedback(
            recallId: recallId,
            messageId: messageId,
            feedbackType: .confirm,
            context: context
        )
    }
    
    // MARK: - Reject Candidate
    
    func rejectCandidate(
        recallId: UUID,
        candidateTitle: String? = nil,
        candidateArtist: String? = nil,
        messageId: UUID? = nil
    ) async throws {
        var context: [String: Any] = [
            "action": "rejected"
        ]
        
        if let title = candidateTitle {
            context["candidate_title"] = title
        }
        
        if let artist = candidateArtist {
            context["candidate_artist"] = artist
        }
        
        try await submitFeedback(
            recallId: recallId,
            messageId: messageId,
            feedbackType: .reject,
            context: context
        )
    }
    
    // MARK: - Correct Song Info
    
    func correctSongInfo(
        recallId: UUID,
        originalTitle: String?,
        originalArtist: String?,
        correctedTitle: String,
        correctedArtist: String,
        messageId: UUID? = nil
    ) async throws {
        var context: [String: Any] = [
            "corrected_title": correctedTitle,
            "corrected_artist": correctedArtist
        ]
        
        if let originalTitle = originalTitle {
            context["original_title"] = originalTitle
        }
        
        if let originalArtist = originalArtist {
            context["original_artist"] = originalArtist
        }
        
        try await submitFeedback(
            recallId: recallId,
            messageId: messageId,
            feedbackType: .correct,
            correctionText: "\(correctedTitle) by \(correctedArtist)",
            context: context
        )
    }
    
    // MARK: - Rate Answer
    
    func rateAnswer(
        recallId: UUID,
        rating: Int, // 1-5
        messageId: UUID? = nil
    ) async throws {
        guard rating >= 1 && rating <= 5 else {
            throw NSError(domain: "RecallFeedbackService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Rating must be between 1 and 5"])
        }
        
        try await submitFeedback(
            recallId: recallId,
            messageId: messageId,
            feedbackType: .rate,
            rating: rating,
            context: ["action": "rated"]
        )
    }
    
    // MARK: - Implicit Feedback (Share/Post/Save)
    
    func recordImplicitFeedback(
        recallId: UUID,
        action: String, // "share", "post", "save"
        candidateTitle: String? = nil,
        candidateArtist: String? = nil
    ) async throws {
        // Implicit feedback is treated as a confirmation
        if let title = candidateTitle, let artist = candidateArtist {
            try await confirmCandidate(
                recallId: recallId,
                candidateTitle: title,
                candidateArtist: artist
            )
        } else {
            // Just record the action
            let context: [String: Any] = [
                "action": action,
                "implicit": true
            ]
            
            try await submitFeedback(
                recallId: recallId,
                feedbackType: .confirm,
                context: context
            )
        }
    }
}




