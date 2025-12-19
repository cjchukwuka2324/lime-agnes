import SwiftUI

struct RecallFeedbackView: View {
    let recallId: UUID
    let messageId: UUID?
    let candidateTitle: String?
    let candidateArtist: String?
    let answerText: String?
    
    @State private var rating: Int = 0
    @State private var correctionText: String = ""
    @State private var showCorrectionInput = false
    @State private var feedbackSubmitted = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Thumbs up/down
            HStack(spacing: 24) {
                Button(action: {
                    Task {
                        try? await RecallFeedbackService.shared.submitFeedback(
                            recallId: recallId,
                            messageId: messageId,
                            feedbackType: .confirm,
                            context: buildContext()
                        )
                        feedbackSubmitted = true
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.title2)
                            .foregroundColor(feedbackSubmitted ? Color(hex: "#1ED760") : .gray)
                        Text("Helpful")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .disabled(feedbackSubmitted)
                
                Button(action: {
                    Task {
                        try? await RecallFeedbackService.shared.submitFeedback(
                            recallId: recallId,
                            messageId: messageId,
                            feedbackType: .reject,
                            context: buildContext()
                        )
                        feedbackSubmitted = true
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.title2)
                            .foregroundColor(feedbackSubmitted ? .red : .gray)
                        Text("Not helpful")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .disabled(feedbackSubmitted)
            }
            
            // Rating (for knowledge answers)
            if answerText != nil {
                VStack(spacing: 8) {
                    Text("Rate this answer")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: {
                                rating = star
                                Task {
                                    try? await RecallFeedbackService.shared.rateAnswer(
                                        recallId: recallId,
                                        rating: star,
                                        messageId: messageId
                                    )
                                }
                            }) {
                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .foregroundColor(star <= rating ? .yellow : .gray)
                                    .font(.title3)
                            }
                        }
                    }
                }
            }
            
            // Correction button (for candidates)
            if candidateTitle != nil && candidateArtist != nil {
                Button(action: {
                    showCorrectionInput.toggle()
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Correct this")
                    }
                    .font(.caption)
                    .foregroundColor(Color(hex: "#1ED760"))
                }
                
                if showCorrectionInput {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Corrected song title", text: $correctionText)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.words)
                        
                        Button("Submit correction") {
                            Task {
                                if !correctionText.isEmpty {
                                    let parts = correctionText.split(separator: " by ")
                                    if parts.count >= 2 {
                                        let correctedTitle = String(parts[0])
                                        let correctedArtist = String(parts[1])
                                        
                                        try? await RecallFeedbackService.shared.correctSongInfo(
                                            recallId: recallId,
                                            originalTitle: candidateTitle,
                                            originalArtist: candidateArtist,
                                            correctedTitle: correctedTitle,
                                            correctedArtist: correctedArtist,
                                            messageId: messageId
                                        )
                                        
                                        showCorrectionInput = false
                                        correctionText = ""
                                    }
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundColor(Color(hex: "#1ED760"))
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
    }
    
    private func buildContext() -> [String: Any] {
        var context: [String: Any] = [:]
        
        if let title = candidateTitle {
            context["candidate_title"] = title
        }
        
        if let artist = candidateArtist {
            context["candidate_artist"] = artist
        }
        
        if let answer = answerText {
            context["answer_text"] = answer
        }
        
        return context
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        RecallFeedbackView(
            recallId: UUID(),
            messageId: nil,
            candidateTitle: "Bohemian Rhapsody",
            candidateArtist: "Queen",
            answerText: nil
        )
        .padding()
    }
}







