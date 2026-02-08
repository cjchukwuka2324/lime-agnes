import Foundation
import AVFoundation
import Combine

/// Manages audio I/O for Recall Voice Mode: capture stream, level metering, playAndRecord session.
/// Provides raw buffers for VAD/STT and level for orb animation.
@MainActor
final class AudioIOManager: ObservableObject {
    static let shared = AudioIOManager()

    @Published var isCapturing: Bool = false
    @Published var audioLevel: CGFloat = 0.0
    @Published var lastError: Error?

    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Called synchronously on audio thread — for STT append. Buffer is valid only during the call.
    var onAudioBufferForSTT: ((AVAudioPCMBuffer) -> Void)?
    /// Called on MainActor with computed level — for VAD (avoids buffer staleness).
    var onAudioLevel: ((Float) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()

    private var lastBufferLevel: Float = 0
    private let levelUpdateInterval: TimeInterval = 0.05
    private var levelTimer: Timer?

    private init() {}

    // MARK: - Configuration

    func configureForVoiceMode() throws {
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try session.setActive(true)
    }

    func deactivate() throws {
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Capture

    func startCapture() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // 512 frames ≈ 11.6 ms at 44.1 kHz — lower latency for faster speech start detection
        inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            let level = Self.computeLevel(from: buffer)
            self?.onAudioBufferForSTT?(buffer)
            Task { @MainActor in
                self?.lastBufferLevel = level
                self?.audioLevel = CGFloat(level)
                self?.onAudioLevel?(level)
                self?.onAudioBuffer?(buffer)
            }
        }

        try audioEngine.start()
        isCapturing = true
        startLevelUpdates()
        Logger.recall.info("AudioIOManager: capture started")
    }

    func stopCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false
        stopLevelUpdates()
        audioLevel = 0
        Logger.recall.info("AudioIOManager: capture stopped")
    }

    // MARK: - Level Metering

    private func startLevelUpdates() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: levelUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateLevel()
            }
        }
        levelTimer?.tolerance = 0.01
        if let timer = levelTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func updateLevel() {
        if isCapturing {
            audioLevel = CGFloat(lastBufferLevel)
        }
    }

    private static func computeLevel(from buffer: AVAudioPCMBuffer) -> Float {
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
            let rms = sqrt(sum / Float(frameLength * channelCount))
            return min(1.0, max(0, rms * 5))
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
            let rms = sqrt(sum / Float(frameLength * channelCount))
            return min(1.0, max(0, rms * 5))
        }
        return 0
    }
}
