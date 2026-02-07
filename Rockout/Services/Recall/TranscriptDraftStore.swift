import Foundation
import SwiftUI

/// Manages transcript draft state (raw and edited transcripts)
/// Handles merge logic for "Append" action (preserves user edits)
@MainActor
final class TranscriptDraftStore: ObservableObject {
    @Published var rawTranscript: String?
    @Published var editedTranscript: String?
    
    /// The final text to use (edited if present, else raw)
    var finalText: String? {
        editedTranscript ?? rawTranscript
    }
    
    /// Set raw transcript (from speech recognition)
    func setRawTranscript(_ text: String) {
        rawTranscript = text
        // If edited transcript is empty or same as raw, clear it
        if editedTranscript == text || editedTranscript?.isEmpty == true {
            editedTranscript = nil
        }
    }
    
    /// Set edited transcript (from user edits)
    func setEditedTranscript(_ text: String) {
        editedTranscript = text.isEmpty ? nil : text
    }
    
    /// Append new text to existing transcript (preserves user edits)
    /// If user has edited, append to edited version; otherwise append to raw
    func appendTranscript(_ newText: String) {
        if let edited = editedTranscript, !edited.isEmpty {
            // User has made edits, append to edited version
            editedTranscript = edited + " " + newText
        } else if let raw = rawTranscript {
            // No edits yet, append to raw
            rawTranscript = raw + " " + newText
        } else {
            // No existing transcript, set as new
            rawTranscript = newText
        }
    }
    
    /// Clear all transcript state
    func clear() {
        rawTranscript = nil
        editedTranscript = nil
    }
    
    /// Merge logic: when appending, preserve user edits
    /// Returns the text that should be used for the next append
    func getTextForAppend() -> String {
        editedTranscript ?? rawTranscript ?? ""
    }
}






