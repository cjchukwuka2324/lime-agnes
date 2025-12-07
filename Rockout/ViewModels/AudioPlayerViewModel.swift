import Foundation
import AVFoundation
import Combine
import SwiftUI
import Supabase

@MainActor
class AudioPlayerViewModel: ObservableObject {
    static let shared = AudioPlayerViewModel()
    
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
    @Published var currentAlbum: StudioAlbumRecord?
    @Published var albumTracks: [StudioTrackRecord] = []
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerForObserver: AVPlayer? // Track which player the observer belongs to
    private var playerItem: AVPlayerItem?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var pitchNode: AVAudioUnitTimePitch?
    private var rateNode: AVAudioUnitVarispeed?
    private var cancellables = Set<AnyCancellable>()
    
    var currentTrack: StudioTrackRecord?
    
    // Play tracking
    private var thresholdRecordedForCurrentTrack: Bool = false
    private var lastTrackedAlbumForReplay: UUID? // Track which album we last incremented replay for
    private let trackPlayService = TrackPlayService.shared
    
    private init() {}
    
    // MARK: - Load Track
    func loadTrack(_ track: StudioTrackRecord, album: StudioAlbumRecord? = nil, tracks: [StudioTrackRecord]? = nil) {
        let previousAlbumId = currentAlbum?.id
        
        currentTrack = track
        if let album = album {
            currentAlbum = album
        }
        if let tracks = tracks {
            albumTracks = tracks.sorted { ($0.track_number ?? 0) < ($1.track_number ?? 0) }
        }
        // If tracks not provided but album matches, keep existing tracks
        // If album changes, clear tracks (will need to be reloaded)
        if tracks == nil, let album = album, currentAlbum?.id != album.id {
            albumTracks = []
        }
        isLoading = true
        errorMessage = nil
        
        // Reset play tracking for new track
        thresholdRecordedForCurrentTrack = false
        
        // Check if we should increment replay count (for discovered albums)
        // Only increment once per album per session to avoid counting every track switch
        if let currentAlbum = currentAlbum, 
           lastTrackedAlbumForReplay != currentAlbum.id {
            // Check if this is a replay of a completed discovered album
            Task {
                do {
                    try await trackPlayService.incrementReplayCountIfNeeded(albumId: currentAlbum.id)
                    // Mark that we've tracked replay for this album in this session
                    await MainActor.run {
                        lastTrackedAlbumForReplay = currentAlbum.id
                    }
                } catch {
                    // Silently fail - replay tracking is not critical
                }
            }
        }
        
        // Remove time observer BEFORE stopping/creating new player
        removeTimeObserver()
        
        // Stop current playback
        stop()
        
        // Try to get a playable URL (signed URL if needed)
        Task {
            do {
                let playableURL = try await getPlayableAudioURL(from: track.audio_url)
                
                await MainActor.run {
                    // Configure AVPlayer for remote playback
                    let asset = AVURLAsset(url: playableURL)
                    self.playerItem = AVPlayerItem(asset: asset)
                    self.player = AVPlayer(playerItem: self.playerItem)
                    
                    // Configure audio session for playback
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                        try AVAudioSession.sharedInstance().setActive(true)
                    } catch {
                        print("Failed to configure audio session: \(error)")
                    }
                    
                    // Observe duration
                    self.playerItem?.publisher(for: \.duration)
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
                        .store(in: &self.cancellables)
                    
                    // Observe status
                    self.playerItem?.publisher(for: \.status)
                        .sink { [weak self] status in
                            guard let self = self else { return }
                            if status == .readyToPlay {
                                self.isLoading = false
                                // Auto-play when ready
                                self.player?.play()
                                self.player?.rate = self.playbackRate
                                self.isPlaying = true
                            } else if status == .failed {
                                // Try to get more detailed error info
                                if let error = self.playerItem?.error {
                                    print("❌ AVPlayerItem error: \(error.localizedDescription)")
                                    if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
                                        print("   Underlying error: \(underlyingError.localizedDescription)")
                                    }
                                }
                                
                                self.errorMessage = "Failed to load audio file"
                                self.isLoading = false
                            }
                        }
                        .store(in: &self.cancellables)
                    
                    // Setup time observer
                    self.setupTimeObserver()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load audio: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    // MARK: - Get Playable Audio URL
    private func getPlayableAudioURL(from audioURLString: String) async throws -> URL {
        print("🎵 Loading audio from URL: \(audioURLString)")
        
        guard let originalURL = URL(string: audioURLString) else {
            throw NSError(domain: "AudioPlayerViewModel", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL"])
        }
        
        // Check if this is a Supabase storage URL
        // Supabase storage URLs typically look like: https://[project].supabase.co/storage/v1/object/public/[bucket]/[path]
        if let host = originalURL.host, host.contains("supabase.co") {
            print("🔍 Detected Supabase storage URL")
            // Try to extract the bucket and path from the URL
            let pathComponents = originalURL.pathComponents
            print("   Path components: \(pathComponents)")
            
            if let publicIndex = pathComponents.firstIndex(of: "public"),
               publicIndex + 1 < pathComponents.count {
                let bucket = pathComponents[publicIndex + 1]
                let filePath = pathComponents.dropFirst(publicIndex + 2).joined(separator: "/")
                
                print("   Extracted bucket: '\(bucket)', path: '\(filePath)'")
                
                // Try to create a signed URL first (works even if bucket is public)
                print("   Attempting to create signed URL for path: '\(filePath)' in bucket: '\(bucket)'...")
                do {
                    let supabase = SupabaseService.shared.client
                    
                    // First, try to verify the file exists by listing the directory
                    let pathComponents = filePath.split(separator: "/")
                    if pathComponents.count >= 2 {
                        let directoryPath = pathComponents.dropLast().joined(separator: "/")
                        let fileName = String(pathComponents.last ?? "")
                        
                        print("   Checking if file exists in directory: '\(directoryPath)'...")
                        do {
                            let files = try await supabase.storage
                                .from(bucket)
                                .list(path: directoryPath)
                            
                            let matchingFiles = files.filter { $0.name == fileName }
                            if matchingFiles.isEmpty {
                                print("   ⚠️ File '\(fileName)' not found in directory '\(directoryPath)'")
                                print("   Available files: \(files.map { $0.name })")
                            } else {
                                print("   ✅ File found in storage")
                            }
                        } catch {
                            print("   ⚠️ Could not list directory (may be RLS issue): \(error.localizedDescription)")
                        }
                    }
                    
                    let signedURL = try await supabase.storage
                        .from(bucket)
                        .createSignedURL(path: filePath, expiresIn: 3600)
                    
                    print("✅ Created signed URL: \(signedURL.absoluteString)")
                    return signedURL
                } catch {
                    print("⚠️ Failed to create signed URL: \(error.localizedDescription)")
                    if let nsError = error as NSError? {
                        print("   Error domain: \(nsError.domain), code: \(nsError.code)")
                        if let userInfo = nsError.userInfo as? [String: Any] {
                            print("   Error userInfo: \(userInfo)")
                        }
                    }
                    
                    // If signed URL fails with "Object not found", the file might not exist
                    // or the path is incorrect. Try public URL as fallback anyway.
                    print("   Falling back to public URL...")
                    print("   NOTE: If this also fails, check:")
                    print("   1. The file exists at path: \(filePath)")
                    print("   2. The '\(bucket)' bucket is public OR has proper RLS policies")
                    print("   3. The storage bucket allows signed URL creation")
                    return originalURL
                }
            } else {
                print("⚠️ Could not extract bucket/path from Supabase URL, using public URL")
            }
        } else {
            print("ℹ️ Not a Supabase URL, using as-is")
        }
        
        // If not a Supabase URL or extraction failed, use the original URL
        return originalURL
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
    
    // MARK: - Track Navigation
    func previousTrack() {
        guard let currentTrack = currentTrack,
              !albumTracks.isEmpty else { return }
        
        let sortedTracks = albumTracks.sorted { ($0.track_number ?? 0) < ($1.track_number ?? 0) }
        guard let currentIndex = sortedTracks.firstIndex(where: { $0.id == currentTrack.id }),
              currentIndex > 0 else { return }
        
        let previousTrack = sortedTracks[currentIndex - 1]
        loadTrack(previousTrack, album: currentAlbum, tracks: albumTracks)
    }
    
    func nextTrack() {
        guard let currentTrack = currentTrack,
              !albumTracks.isEmpty else { return }
        
        let sortedTracks = albumTracks.sorted { ($0.track_number ?? 0) < ($1.track_number ?? 0) }
        guard let currentIndex = sortedTracks.firstIndex(where: { $0.id == currentTrack.id }),
              currentIndex < sortedTracks.count - 1 else { return }
        
        let nextTrack = sortedTracks[currentIndex + 1]
        loadTrack(nextTrack, album: currentAlbum, tracks: albumTracks)
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
        // Remove any existing observer first
        removeTimeObserver()
        
        guard let currentPlayer = player else { return }
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = currentPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.currentTime = time.seconds
            
            // Check and record play if threshold reached
            self.checkAndRecordPlayIfNeeded()
            
            // Handle looping
            if self.isLooping && self.currentTime >= self.loopEnd {
                self.seek(to: self.loopStart)
            }
        }
        
        // Store reference to the player this observer belongs to
        playerForObserver = currentPlayer
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver, let playerToRemoveFrom = playerForObserver {
            // Only remove from the player that added it
            playerToRemoveFrom.removeTimeObserver(observer)
            timeObserver = nil
            playerForObserver = nil
        } else if timeObserver != nil {
            // If we have an observer but no player reference, try current player
            // This handles edge cases
            if let observer = timeObserver, let currentPlayer = player {
                currentPlayer.removeTimeObserver(observer)
            }
            timeObserver = nil
            playerForObserver = nil
        }
    }
    
    nonisolated private func removeTimeObserverUnsafe() {
        // This version can be called from deinit
        // We need to access the properties directly without main actor isolation
        Task { @MainActor in
            self.removeTimeObserver()
        }
    }
    
    // MARK: - Play Tracking
    private func checkAndRecordPlayIfNeeded() {
        // Only record if we haven't already recorded for this track
        guard !thresholdRecordedForCurrentTrack else { return }
        
        // Need track, album, current time, and duration
        guard let track = currentTrack,
              let album = currentAlbum,
              duration > 0 else { return }
        
        // Check if threshold is reached
        let thresholdReached: Bool
        if duration <= 30.0 {
            // For tracks ≤ 30 sec, require 80% playback
            let threshold = duration * 0.8
            thresholdReached = currentTime >= threshold
        } else {
            // For tracks > 30 sec, require 30 seconds playback
            thresholdReached = currentTime >= 30.0
        }
        
        guard thresholdReached else { return }
        
        // Set flag IMMEDIATELY to prevent race condition from multiple rapid calls
        // This prevents duplicate recordings before the async call completes
        thresholdRecordedForCurrentTrack = true
        
        // Record the play asynchronously
        Task {
            do {
                let recorded = try await trackPlayService.checkAndRecordPlay(
                    trackId: track.id,
                    albumId: album.id,
                    durationListened: currentTime,
                    trackDuration: duration
                )
                
                if recorded {
                    print("✅ Play recorded for track: \(track.title)")
                } else {
                    // If recording failed (e.g., already recorded recently), reset flag to allow retry
                    await MainActor.run {
                        self.thresholdRecordedForCurrentTrack = false
                    }
                }
            } catch {
                print("⚠️ Failed to record play: \(error.localizedDescription)")
                // Reset flag on error to allow retry
                await MainActor.run {
                    self.thresholdRecordedForCurrentTrack = false
                }
            }
        }
    }
    
    private func updateAudioEngine() {
        // Full audio engine implementation for pitch would go here
        // This is a placeholder - you'd need to set up AVAudioEngine with pitch node
    }
    
    deinit {
        // Cleanup: remove time observer if it exists
        // We can't call main actor methods from deinit, so we do minimal cleanup
        if let observer = timeObserver, let playerToRemoveFrom = playerForObserver {
            playerToRemoveFrom.removeTimeObserver(observer)
        }
        player?.pause()
        // Note: cancellables will be cleaned up automatically
    }
}

extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

