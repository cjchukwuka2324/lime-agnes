import Foundation
import AVFoundation
import Combine

/// Voice Activity Detection — detects when user starts/stops speaking.
/// Replaces long-press with automatic end-of-utterance.
@MainActor
final class VADService: ObservableObject {
    @Published var isSpeechActive: Bool = false
    @Published var speechStartTime: Date?

    var onSpeechStart: (() -> Void)?
    var onSpeechEnd: (() -> Void)?
    /// When in barge-in mode (TTS speaking), call when user speech is detected.
    var onBargeIn: (() -> Void)?
    /// When true, speech detection triggers onBargeIn instead of onSpeechStart (used during TTS).
    var bargeInMode: Bool = false

    /// Level above which we consider speech (low = responsive; avoids missing quiet starts)
    private let speechThreshold: Float = 0.01
    /// Silence after speech to consider user done (efficient turn-taking; still natural)
    private let silenceDuration: TimeInterval = 0.85
    private let preRollDuration: TimeInterval = 0.4
    /// Minimum utterance length before we accept end (avoid cutting off single syllables)
    private let minUtteranceDuration: TimeInterval = 0.2

    private var lastSpeechTime: Date = .distantPast
    private var silenceTimer: Timer?
    private var hasEmittedSpeechStart = false

    init() {}

    // MARK: - Process Audio

    func processLevel(_ level: Float) {
        let now = Date()

        if level >= speechThreshold {
            lastSpeechTime = now
            silenceTimer?.invalidate()
            silenceTimer = nil

            if bargeInMode {
                onBargeIn?()
                return
            }
            if !hasEmittedSpeechStart {
                hasEmittedSpeechStart = true
                isSpeechActive = true
                speechStartTime = now
                onSpeechStart?()
                Logger.recall.debug("VAD: speech start")
            }
        } else {
            if hasEmittedSpeechStart {
                let elapsed = now.timeIntervalSince(speechStartTime ?? now)
                if elapsed >= minUtteranceDuration {
                    if silenceTimer == nil {
                        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceDuration, repeats: false) { [weak self] _ in
                            Task { @MainActor in
                                self?.handleSpeechEnd()
                            }
                        }
                        silenceTimer?.tolerance = 0.1
                        if let t = silenceTimer {
                            RunLoop.main.add(t, forMode: .common)
                        }
                    }
                }
            }
        }
    }

    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        processLevel(AudioIOManager.computeLevelStatic(from: buffer))
    }

    private func handleSpeechEnd() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasEmittedSpeechStart = false
        isSpeechActive = false
        onSpeechEnd?()
        Logger.recall.debug("VAD: speech end")
    }

    func reset() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasEmittedSpeechStart = false
        isSpeechActive = false
        speechStartTime = nil
    }
}

// Expose static level computation for VAD use
extension AudioIOManager {
    static func computeLevelStatic(from buffer: AVAudioPCMBuffer) -> Float {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        if let channelData = buffer.floatChannelData {
            var sum: Float = 0
            for ch in 0..<channelCount {
                let data = channelData[ch]
                for i in 0..<frameLength {
                    sum += data[i] * data[i]
                }
            }
            return sqrt(sum / Float(frameLength * channelCount))
        }
        if let channelData = buffer.int16ChannelData {
            var sum: Float = 0
            let scale: Float = 1.0 / 32768.0
            for ch in 0..<channelCount {
                let data = channelData[ch]
                for i in 0..<frameLength {
                    let s = Float(data[i]) * scale
                    sum += s * s
                }
            }
            return sqrt(sum / Float(frameLength * channelCount))
        }
        return 0
    }
}
