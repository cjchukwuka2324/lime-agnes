import Foundation

/// Unified request context for Recall feature
/// Combines voice, text, and image inputs into a single request payload
struct RecallRequestContext: Codable {
    enum InputMode: String, Codable {
        case voice
        case text
        case image
        case mixed
    }
    
    struct ImageReference: Codable {
        let path: String
        let type: String // "image" or "video"
    }
    
    let inputMode: InputMode
    let rawTranscript: String?
    let editedTranscript: String?
    let typedText: String?
    let attachedImages: [ImageReference]?
    let audioRef: String? // Only if user opts in
    let deviceLocale: String
    let timestamp: Date
    
    init(
        inputMode: InputMode,
        rawTranscript: String? = nil,
        editedTranscript: String? = nil,
        typedText: String? = nil,
        attachedImages: [ImageReference]? = nil,
        audioRef: String? = nil,
        deviceLocale: String = Locale.current.identifier,
        timestamp: Date = Date()
    ) {
        self.inputMode = inputMode
        self.rawTranscript = rawTranscript
        self.editedTranscript = editedTranscript
        self.typedText = typedText
        self.attachedImages = attachedImages
        self.audioRef = audioRef
        self.deviceLocale = deviceLocale
        self.timestamp = timestamp
    }
    
    /// Get the final text to send (edited transcript takes precedence)
    var finalText: String? {
        if let edited = editedTranscript, !edited.isEmpty {
            return edited
        }
        if let raw = rawTranscript, !raw.isEmpty {
            return raw
        }
        if let typed = typedText, !typed.isEmpty {
            return typed
        }
        return nil
    }
}

