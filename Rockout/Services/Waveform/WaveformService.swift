import Foundation
import AVFoundation
import Supabase

final class WaveformService {
    static let shared = WaveformService()
    private init() {}
    
    private let supabase = SupabaseService.shared.client
    
    // Target number of samples for visualization (200-500 range)
    private let targetSampleCount = 300
    
    // MARK: - Get Waveform Data
    
    /// Fetches cached waveform data from database, or generates it if not cached
    func getWaveformData(for trackId: UUID, audioURL: URL) async throws -> WaveformData {
        // Try to fetch from cache first
        if let cached = try await fetchCachedWaveform(trackId: trackId) {
            return cached
        }
        
        // Generate new waveform data
        let waveformData = try await generateWaveformData(from: audioURL, trackId: trackId)
        
        // Cache it in the database
        try await cacheWaveformData(waveformData)
        
        return waveformData
    }
    
    // MARK: - Generate Waveform Data
    
    /// Generates waveform data from an audio file URL
    func generateWaveformData(from audioURL: URL, trackId: UUID) async throws -> WaveformData {
        // Download audio file if remote
        let localURL: URL
        if audioURL.isFileURL {
            localURL = audioURL
        } else {
            let (tempURL, _) = try await URLSession.shared.download(from: audioURL)
            localURL = tempURL
        }
        
        // Load audio file
        guard let audioFile = try? AVAudioFile(forReading: localURL) else {
            throw NSError(
                domain: "WaveformService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load audio file"]
            )
        }
        
        let format = audioFile.processingFormat
        let frameCount = Int(audioFile.length)
        let channelCount = Int(format.channelCount)
        let sampleRate = Int(format.sampleRate)
        
        // Read audio buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            throw NSError(
                domain: "WaveformService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffer"]
            )
        }
        
        do {
            try audioFile.read(into: buffer)
        } catch {
            throw NSError(
                domain: "WaveformService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read audio file: \(error.localizedDescription)"]
            )
        }
        
        // Process samples into waveform data
        let samples = try processAudioBuffer(buffer, channelCount: channelCount, frameCount: frameCount)
        
        return WaveformData(trackId: trackId, samples: samples, sampleRate: sampleRate)
    }
    
    // MARK: - Process Audio Buffer
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, channelCount: Int, frameCount: Int) throws -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            throw NSError(
                domain: "WaveformService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get channel data"]
            )
        }
        
        // Calculate samples per window (downsample to targetSampleCount)
        let framesPerSample = max(1, frameCount / targetSampleCount)
        var samples: [Float] = []
        
        // Process each window
        for i in 0..<targetSampleCount {
            let startFrame = i * framesPerSample
            let endFrame = min(startFrame + framesPerSample, frameCount)
            
            // Calculate RMS (Root Mean Square) amplitude for this window
            var sumOfSquares: Float = 0.0
            var sampleCount = 0
            
            for frame in startFrame..<endFrame {
                // Average across all channels
                var channelSum: Float = 0.0
                for channel in 0..<channelCount {
                    channelSum += channelData[channel][frame]
                }
                let average = channelSum / Float(channelCount)
                sumOfSquares += average * average
                sampleCount += 1
            }
            
            // Calculate RMS
            let rms = sqrt(sumOfSquares / Float(sampleCount))
            samples.append(rms)
        }
        
        // Normalize to 0-1 range
        if let maxAmplitude = samples.max(), maxAmplitude > 0 {
            samples = samples.map { $0 / maxAmplitude }
        }
        
        return samples
    }
    
    // MARK: - Cache Management
    
    private func fetchCachedWaveform(trackId: UUID) async throws -> WaveformData? {
        do {
            let response = try await supabase
                .from("track_waveforms")
                .select()
                .eq("track_id", value: trackId.uuidString)
                .single()
                .execute()
            
            return try JSONDecoder().decode(WaveformData.self, from: response.data)
        } catch {
            // Not found or error - return nil to trigger generation
            return nil
        }
    }
    
    private func cacheWaveformData(_ waveformData: WaveformData) async throws {
        struct WaveformDTO: Encodable {
            let track_id: String
            let samples: [Double]
            let sample_rate: Int
        }
        
        let dto = WaveformDTO(
            track_id: waveformData.trackId.uuidString,
            samples: waveformData.samples.map { Double($0) },
            sample_rate: waveformData.sampleRate
        )
        
        // Use upsert to handle both insert and update
        try await supabase
            .from("track_waveforms")
            .upsert(dto, onConflict: "track_id")
            .execute()
    }
}
