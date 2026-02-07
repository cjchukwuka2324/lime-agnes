import Foundation
import SwiftUI
import AVFoundation
import Combine

/// Wraps VoiceResponseService with additional caption coordination
/// Tracks which message is currently being spoken
/// Updates UI with live caption highlights
@MainActor
final class TTSManager: ObservableObject {
    static let shared = TTSManager()
    
    @Published var currentMessageId: UUID?
    @Published var isSpeaking: Bool = false
    @Published var currentSpokenText: String = ""
    @Published var fullText: String = ""
    
    private let voiceResponseService = VoiceResponseService.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe VoiceResponseService state
        voiceResponseService.$isSpeaking
            .assign(to: &$isSpeaking)
        
        voiceResponseService.$currentSpokenText
            .assign(to: &$currentSpokenText)
        
        voiceResponseService.$fullText
            .assign(to: &$fullText)
    }
    
    /// Speak text for a specific message
    func speak(_ text: String, messageId: UUID, completion: (() -> Void)? = nil) {
        currentMessageId = messageId
        fullText = text
        voiceResponseService.speak(text, completion: { [weak self] in
            self?.currentMessageId = nil
            completion?()
        })
    }
    
    /// Stop speaking
    func stopSpeaking() {
        voiceResponseService.stopSpeaking()
        currentMessageId = nil
    }
    
    /// Check if a specific message is being spoken
    func isSpeakingMessage(_ messageId: UUID) -> Bool {
        currentMessageId == messageId && isSpeaking
    }
}

