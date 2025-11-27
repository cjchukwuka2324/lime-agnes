import Foundation
import AVFoundation
import Combine
import SwiftUI

@MainActor
class AudioPlayerViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackRate: Float = 1.0
    @Published var pitch: Float = 0.0 // Semitones, -12 to +12
    @Published var volume: Float = 1.0
    @Published var isLooping = false
    @Published var loopStart: TimeInterval = 0
    @Published var loopEnd: TimeInterval = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerItem: AVPlayerItem?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var pitchNode: AVAudioUnitTimePitch?
    private var rateNode: AVAudioUnitVarispeed?
    private var cancellables = Set<AnyCancellable>()
    
    var currentTrack: StudioTrackRecord?
    
    // MARK: - Load Track
    func loadTrack(_ track: StudioTrackRecord) {
        currentTrack = track
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: track.audio_url) else {
            errorMessage = "Invalid audio URL"
            isLoading = false
            return
        }
        
        // Stop current playback
        stop()
        
        // Configure AVPlayer for remote playback
        let asset = AVURLAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        
        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        
        // Observe duration
        playerItem?.publisher(for: \.duration)
            .sink { [weak self] duration in
                guard let self = self, duration.isValid else { return }
                let seconds = duration.seconds
                // Only set if valid (not NaN or Infinity)
                guard seconds.isFinite && !seconds.isNaN else { return }
                self.duration = seconds
                if self.loopEnd == 0 {
                    self.loopEnd = seconds
                }
            }
            .store(in: &cancellables)
        
        // Observe status
        playerItem?.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self = self else { return }
                if status == .readyToPlay {
                    self.isLoading = false
                } else if status == .failed {
                    self.errorMessage = "Failed to load audio"
                    self.isLoading = false
                }
            }
            .store(in: &cancellables)
        
        // Setup time observer
        setupTimeObserver()
    }
    
    // MARK: - Playback Controls
    func play() {
        guard let player = player, let playerItem = playerItem else {
            errorMessage = "Audio not loaded"
            return
        }
        
        // Wait for item to be ready if needed
        if playerItem.status == .readyToPlay {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        } else if playerItem.status == .failed {
            errorMessage = "Failed to load audio file"
        } else {
            // Item is still loading, wait a bit and try again
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                if playerItem.status == .readyToPlay {
                    await MainActor.run {
                        player.play()
                        player.rate = playbackRate
                        isPlaying = true
                    }
                }
            }
        }
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        currentTime = 0
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
    }
    
    // MARK: - Playback Rate
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }
    
    // MARK: - Pitch Adjustment
    func setPitch(_ semitones: Float) {
        pitch = semitones.clamped(to: -12...12)
        // For pitch adjustment, we'd need to use AVAudioEngine
        // This is a simplified version - full implementation would use audio engine
        updateAudioEngine()
    }
    
    // MARK: - Loop Controls
    func setLoop(start: TimeInterval, end: TimeInterval) {
        loopStart = start
        loopEnd = end
        isLooping = true
    }
    
    func toggleLoop() {
        isLooping.toggle()
        if !isLooping {
            loopStart = 0
            loopEnd = duration
        }
    }
    
    // MARK: - Trim (returns trimmed audio data)
    func trimTrack(startTime: TimeInterval, endTime: TimeInterval) async throws -> Data? {
        guard let playerItem = playerItem,
              let asset = playerItem.asset as? AVURLAsset else {
            throw NSError(domain: "AudioPlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio loaded"])
        }
        
        let composition = AVMutableComposition()
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "AudioPlayer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio track"])
        }
        
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "AudioPlayer", code: 3, userInfo: [NSLocalizedDescriptionKey: "No audio track found"])
        }
        
        let startCM = CMTime(seconds: startTime, preferredTimescale: 600)
        let durationCM = CMTime(seconds: endTime - startTime, preferredTimescale: 600)
        let timeRange = CMTimeRange(start: startCM, duration: durationCM)
        
        try audioTrack.insertTimeRange(timeRange, of: sourceTrack, at: .zero)
        
        // Export trimmed audio
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "AudioPlayer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        await exportSession.export()
        
        guard exportSession.status == .completed else {
            throw exportSession.error ?? NSError(domain: "AudioPlayer", code: 5, userInfo: [NSLocalizedDescriptionKey: "Export failed"])
        }
        
        return try Data(contentsOf: outputURL)
    }
    
    // MARK: - Private Methods
    private func setupTimeObserver() {
        removeTimeObserver()
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            
            // Handle looping
            if self.isLooping && self.currentTime >= self.loopEnd {
                self.seek(to: self.loopStart)
            }
        }
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    private func updateAudioEngine() {
        // Full audio engine implementation for pitch would go here
        // This is a placeholder - you'd need to set up AVAudioEngine with pitch node
    }
    
    deinit {
        // Cleanup directly without calling main actor methods
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        cancellables.removeAll()
    }
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

