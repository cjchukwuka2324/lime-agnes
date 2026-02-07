import Foundation
import AVFoundation
import UIKit

@MainActor
class VoiceResponseService: NSObject, ObservableObject {
    static let shared = VoiceResponseService()
    
    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    @Published var currentSpokenText: String = "" // Live transcript of what's currently being spoken
    @Published var fullText: String = "" // Full text being spoken
    
    private var completionHandler: (() -> Void)?
    private var currentUtterance: AVSpeechUtterance?
    
    private override init() {
        super.init()
        synthesizer.delegate = self
        
        // Listen for app lifecycle events to stop speaking when app goes to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func appWillResignActive() {
        // Stop speaking when app becomes inactive (e.g., user switches apps)
        Task { @MainActor in
            if self.isSpeaking {
                self.stopSpeaking()
                print("🔇 [LIFECYCLE] Stopped speaking because app will resign active")
            }
        }
    }
    
    @objc private func appDidEnterBackground() {
        // Stop speaking when app enters background
        Task { @MainActor in
            if self.isSpeaking {
                self.stopSpeaking()
                print("🔇 [LIFECYCLE] Stopped speaking because app entered background")
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        stopSpeaking()
        
        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            print("✅ Audio session configured for TTS playback")
        } catch {
            print("❌ Failed to configure audio session for TTS: \(error)")
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Store full text and reset current spoken text
        fullText = text
        currentSpokenText = ""
        currentUtterance = utterance
        
        completionHandler = completion
        isSpeaking = true
        synthesizer.speak(utterance)
        print("🗣️ Speaking: \(text)")
    }
    
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        currentSpokenText = ""
        fullText = ""
        currentUtterance = nil
        completionHandler = nil
    }
    
    func pauseSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }
    
    func continueSpeaking() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }
}

extension VoiceResponseService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
            currentSpokenText = "" // Reset at start
        }
    }
    
    // This delegate method is called when a word is about to be spoken
    // We use it to update the live transcript
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let fullString = utterance.speechString
            // Update currentSpokenText to show everything up to and including the current word
            let endIndex = min(characterRange.location + characterRange.length, fullString.count)
            if endIndex > 0 {
                let index = fullString.index(fullString.startIndex, offsetBy: endIndex)
                let newText = String(fullString[..<index])
                currentSpokenText = newText
                print("📝 [TRANSCRIPT] Updated currentSpokenText: '\(newText.prefix(50))' (length: \(newText.count))")
            }
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            print("✅ TTS finished speaking")
            isSpeaking = false
            // Show full text when finished
            currentSpokenText = fullText
            
            // Deactivate audio session after speaking
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
                print("✅ Audio session deactivated after TTS")
            } catch {
                print("❌ Failed to deactivate audio session: \(error)")
            }
            
            let handler = completionHandler
            completionHandler = nil
            handler?()
        }
    }
    
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            currentSpokenText = ""
            fullText = ""
            currentUtterance = nil
            completionHandler = nil
        }
    }
}



