import Foundation
import AVFoundation

/// Heuristic audio type classifier: speech, music, hum, noise.
/// Uses energy (RMS), zero-crossing rate, and spectral features.
@MainActor
final class AudioTypeClassifier {
    static let shared = AudioTypeClassifier()

    private init() {}

    /// Classify audio from PCM buffer. Run on MainActor.
    func classify(buffer: AVAudioPCMBuffer) -> AudioClassificationType {
        let samples = extractSamples(from: buffer)
        guard !samples.isEmpty else { return .noise }

        let rms = computeRMS(samples)
        let zcr = computeZeroCrossingRate(samples)
        let energyVariance = computeEnergyVariance(samples, windowSize: 512)

        // Very low energy → noise
        if rms < 0.005 {
            return .noise
        }

        // Low ZCR + sustained energy → music (harmonic content)
        if zcr < 0.02, rms > 0.03, energyVariance < 0.001 {
            return .music
        }

        // Very low ZCR + moderate energy → hum (single tone)
        if zcr < 0.015, rms > 0.02, rms < 0.15 {
            return .hum
        }

        // Moderate ZCR + variable energy → speech
        if zcr > 0.02, zcr < 0.12 {
            return .speech
        }

        // High ZCR → noise or sibilant speech; default to speech for usability
        if rms > 0.02 {
            return .speech
        }

        return .noise
    }

    /// Classify from multiple buffers (e.g. accumulated during capture).
    func classify(buffers: [AVAudioPCMBuffer]) -> AudioClassificationType {
        var votes: [AudioClassificationType: Int] = [:]
        for buffer in buffers {
            let type = classify(buffer: buffer)
            votes[type, default: 0] += 1
        }
        return votes.max(by: { $0.value < $1.value })?.key ?? .speech
    }

    /// Classify from audio file URL (e.g. VoiceRecorder output).
    func classify(file url: URL) -> AudioClassificationType? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(min(16000, file.length))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        do {
            try file.read(into: buffer)
            return classify(buffer: buffer)
        } catch {
            Logger.recall.error("AudioTypeClassifier file read failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private

    private func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return [] }

        var samples: [Float] = []
        if let channelData = buffer.floatChannelData {
            for ch in 0..<channelCount {
                let data = channelData[ch]
                for i in 0..<frameLength {
                    samples.append(data[i])
                }
            }
        } else if let channelData = buffer.int16ChannelData {
            let scale: Float = 1.0 / 32768.0
            for ch in 0..<channelCount {
                let data = channelData[ch]
                for i in 0..<frameLength {
                    samples.append(Float(data[i]) * scale)
                }
            }
        }
        return samples
    }

    private func computeRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sum / Float(samples.count))
    }

    private func computeZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i - 1] >= 0 && samples[i] < 0) || (samples[i - 1] < 0 && samples[i] >= 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count - 1)
    }

    private func computeEnergyVariance(_ samples: [Float], windowSize: Int) -> Float {
        guard samples.count >= windowSize else { return 0 }
        var energies: [Float] = []
        var i = 0
        while i + windowSize <= samples.count {
            let window = Array(samples[i..<(i + windowSize)])
            energies.append(computeRMS(window))
            i += windowSize
        }
        guard !energies.isEmpty else { return 0 }
        let mean = energies.reduce(0, +) / Float(energies.count)
        let variance = energies.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(energies.count)
        return variance
    }
}
