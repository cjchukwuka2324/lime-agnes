import Foundation
import AVFoundation
import Combine
import SwiftUI
import Supabase
import MediaPlayer
import UIKit

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
    @Published var currentTrack: StudioTrackRecord?
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var playerForObserver: AVPlayer? // Track which player the observer belongs to
    private var playerItem: AVPlayerItem?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var pitchNode: AVAudioUnitTimePitch?
    private var rateNode: AVAudioUnitVarispeed?
    private var cancellables = Set<AnyCancellable>()
    
    // Now Playing artwork cache
    private var cachedArtwork: MPMediaItemArtwork?
    private var currentArtworkAlbumId: UUID?
    
    // Play tracking
    private var thresholdRecordedForCurrentTrack: Bool = false
    private var lastTrackedAlbumForReplay: UUID? // Track which album we last incremented replay for
    private let trackPlayService = TrackPlayService.shared
    
    private init() {
        setupRemoteCommandCenter()
    }
    
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
        
        // Reset artwork cache to force reload when track changes
        currentArtworkAlbumId = nil
        cachedArtwork = nil
        
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
        
        // Stop current playback and audio engine
        stop()
        stopAudioEngine()
        
        // Try to get a playable URL (signed URL if needed)
        Task {
            do {
                let playableURL = try await getPlayableAudioURL(from: track.audio_url)
                
                await MainActor.run {
                    // Configure AVPlayer for remote playback
                    let asset = AVURLAsset(url: playableURL)
                    self.playerItem = AVPlayerItem(asset: asset)
                    self.player = AVPlayer(playerItem: self.playerItem)
                    
                    // Configure audio session for playback with background and Bluetooth support
                    do {
                        let audioSession = AVAudioSession.sharedInstance()
                        try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
                        try audioSession.setActive(true)
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
                                // Update Now Playing info immediately when track is ready
                                self.updateNowPlayingInfo()
                                // Auto-play when ready
                                self.player?.play()
                                self.player?.rate = self.playbackRate
                                self.isPlaying = true
                                // Update again after starting playback to ensure playback rate is set
                                self.updateNowPlayingInfo()
                            } else if status == .failed {
                                // DIAGNOSTIC: Get detailed error info
                                var errorDetails: [String] = []
                                
                                if let error = self.playerItem?.error {
                                    let errorDescription = error.localizedDescription
                                    let errorCode = (error as NSError).code
                                    errorDetails.append("Error: \(errorDescription)")
                                    errorDetails.append("Code: \(errorCode)")
                                    
                                    print("❌ AVPlayerItem error: \(errorDescription)")
                                    print("   Error code: \(errorCode)")
                                    
                                    if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
                                        let underlyingCode = underlyingError.code
                                        let underlyingDesc = underlyingError.localizedDescription
                                        errorDetails.append("Underlying: \(underlyingDesc) (code: \(underlyingCode))")
                                        print("   Underlying error: \(underlyingDesc)")
                                        print("   Underlying code: \(underlyingCode)")
                                    }
                                    
                                    // Log the URL being used
                                    if let currentTrack = self.currentTrack {
                                        print("   Track URL: \(currentTrack.audio_url)")
                                        errorDetails.append("URL: \(currentTrack.audio_url)")
                                    }
                                    
                                    // Check asset status
                                    if let asset = self.playerItem?.asset as? AVURLAsset {
                                        print("   Asset URL: \(asset.url.absoluteString)")
                                        errorDetails.append("Asset URL: \(asset.url.absoluteString)")
                                        
                                        // Check if we can access the URL
                                        Task {
                                            do {
                                                var request = URLRequest(url: asset.url)
                                                request.httpMethod = "HEAD"
                                                request.timeoutInterval = 5.0
                                                let (_, response) = try await URLSession.shared.data(for: request)
                                                if let httpResponse = response as? HTTPURLResponse {
                                                    print("   🔍 URL accessibility check: HTTP \(httpResponse.statusCode)")
                                                    errorDetails.append("HTTP Status: \(httpResponse.statusCode)")
                                                }
                                            } catch {
                                                print("   🔍 URL accessibility check failed: \(error.localizedDescription)")
                                                errorDetails.append("URL check error: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                }
                                
                                // Set user-friendly error message
                                let userMessage = errorDetails.isEmpty ? "Failed to load audio file" : errorDetails.joined(separator: "\n")
                                self.errorMessage = "Failed to load audio file"
                                self.isLoading = false
                                
                                // Log full diagnostic info
                                print("📊 FULL DIAGNOSTIC INFO:")
                                errorDetails.forEach { print("   \($0)") }
                            }
                        }
                        .store(in: &self.cancellables)
                    
                    // Setup time observer
                    self.setupTimeObserver()
                    
                    // Update remote command center availability after track loads
                    self.updateRemoteCommandCenterAvailability()
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
                
                print("   📦 Extracted bucket: '\(bucket)', path: '\(filePath)'")
                
                // DIAGNOSTIC STEP 1: Verify file exists in storage
                print("   🔍 STEP 1: Checking if file exists in storage...")
                let supabase = SupabaseService.shared.client
                let pathComponents = filePath.split(separator: "/")
                var fileExists = false
                
                if pathComponents.count >= 2 {
                    let directoryPath = pathComponents.dropLast().joined(separator: "/")
                    let fileName = String(pathComponents.last ?? "")
                    
                    print("      Directory: '\(directoryPath)'")
                    print("      Filename: '\(fileName)'")
                    
                    do {
                        let files = try await supabase.storage
                            .from(bucket)
                            .list(path: directoryPath)
                        
                        let matchingFiles = files.filter { $0.name == fileName }
                        if matchingFiles.isEmpty {
                            print("      ❌ FILE NOT FOUND in storage!")
                            print("      Available files in directory: \(files.map { $0.name })")
                            fileExists = false
                        } else {
                            print("      ✅ File found in storage")
                            if let fileInfo = matchingFiles.first {
                                print("      File size: \(fileInfo.metadata?["size"] ?? "unknown") bytes")
                            }
                            fileExists = true
                        }
                    } catch {
                        print("      ⚠️ Could not list directory: \(error.localizedDescription)")
                        print("      This might be an RLS (Row Level Security) issue")
                        // Continue anyway - file might exist but we can't list
                    }
                } else {
                    print("      ⚠️ Could not parse file path components")
                }
                
                // DIAGNOSTIC STEP 2: Try to create signed URL
                print("   🔍 STEP 2: Attempting to create signed URL...")
                do {
                    let signedURL = try await supabase.storage
                        .from(bucket)
                        .createSignedURL(path: filePath, expiresIn: 3600)
                    
                    print("      ✅ Created signed URL successfully")
                    print("      Signed URL: \(signedURL.absoluteString)")
                    return signedURL
                } catch {
                    print("      ❌ Failed to create signed URL")
                    print("      Error: \(error.localizedDescription)")
                    
                    if let nsError = error as NSError? {
                        print("      Error domain: \(nsError.domain), code: \(nsError.code)")
                        if let userInfo = nsError.userInfo as? [String: Any] {
                            print("      Error details: \(userInfo)")
                        }
                    }
                    
                    // DIAGNOSTIC STEP 3: Check error type
                    let errorDescription = error.localizedDescription.lowercased()
                    if errorDescription.contains("not found") || errorDescription.contains("404") {
                        print("      🔍 DIAGNOSIS: File not found error")
                        if !fileExists {
                            print("      ❌ CONFIRMED: File does not exist in storage")
                        }
                    } else if errorDescription.contains("permission") || errorDescription.contains("forbidden") || errorDescription.contains("403") {
                        print("      🔍 DIAGNOSIS: Permission denied - RLS policy may be blocking access")
                    } else if errorDescription.contains("timeout") || errorDescription.contains("network") {
                        print("      🔍 DIAGNOSIS: Network/timeout error")
                    }
                    
                    // DIAGNOSTIC STEP 4: Fallback to public URL
                    print("   🔍 STEP 3: Falling back to public URL...")
                    print("      Public URL: \(originalURL.absoluteString)")
                    print("   📝 NOTE: If playback still fails, check:")
                    print("      1. File exists at path: \(filePath) in bucket: \(bucket)")
                    print("      2. Bucket '\(bucket)' is public OR has proper RLS policies")
                    print("      3. Storage bucket allows signed URL creation")
                    print("      4. File format is supported (m4a, mp3, etc.)")
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
        // If using audio engine for pitch, use that
        if pitch != 0, let playerNode = playerNode, let engine = audioEngine, engine.isRunning {
            playerNode.play()
            isPlaying = true
            updateNowPlayingInfo()
            return
        }
        
        guard let player = player, let playerItem = playerItem else {
            errorMessage = "Audio not loaded"
            return
        }
        
        // Wait for item to be ready if needed
        if playerItem.status == .readyToPlay {
            player.play()
            player.rate = playbackRate
            isPlaying = true
            updateNowPlayingInfo()
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
                        updateNowPlayingInfo()
                    }
                }
            }
        }
    }
    
    func pause() {
        if let playerNode = playerNode {
            playerNode.pause()
        } else {
            player?.pause()
        }
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        currentTime = 0
    }
    
    func dismiss() {
        removeTimeObserver()
        player?.pause()
        player?.seek(to: .zero)
        player = nil
        playerItem = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentTrack = nil
        currentAlbum = nil
        albumTracks = []
        thresholdRecordedForCurrentTrack = false
        lastTrackedAlbumForReplay = nil
        
        // Clear Now Playing info and artwork cache
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        cachedArtwork = nil
        currentArtworkAlbumId = nil
        updateRemoteCommandCenterAvailability()
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
    }
    
    // MARK: - Track Navigation
    func previousTrack() {
        guard let currentTrack = currentTrack,
              !albumTracks.isEmpty else {
            print("⚠️ Cannot go to previous track: no current track or album tracks")
            return
        }
        
        let sortedTracks = albumTracks.sorted { ($0.track_number ?? 0) < ($1.track_number ?? 0) }
        guard let currentIndex = sortedTracks.firstIndex(where: { $0.id == currentTrack.id }) else {
            print("⚠️ Cannot find current track in album tracks")
            return
        }
        
        if currentIndex > 0 {
            // Go to previous track
            let previousTrack = sortedTracks[currentIndex - 1]
            print("▶️ Loading previous track: \(previousTrack.title)")
            loadTrack(previousTrack, album: currentAlbum, tracks: albumTracks)
        } else {
            // At first track - restart current song
            print("ℹ️ At first track, restarting current song")
            seek(to: 0)
            if !isPlaying {
                play()
            }
            updateNowPlayingInfo()
        }
    }
    
    func nextTrack() {
        guard let currentTrack = currentTrack,
              !albumTracks.isEmpty else {
            print("⚠️ Cannot go to next track: no current track or album tracks")
            return
        }
        
        let sortedTracks = albumTracks.sorted { ($0.track_number ?? 0) < ($1.track_number ?? 0) }
        guard let currentIndex = sortedTracks.firstIndex(where: { $0.id == currentTrack.id }) else {
            print("⚠️ Cannot find current track in album tracks")
            return
        }
        
        if currentIndex < sortedTracks.count - 1 {
            // Go to next track
            let nextTrack = sortedTracks[currentIndex + 1]
            print("▶️ Loading next track: \(nextTrack.title)")
            loadTrack(nextTrack, album: currentAlbum, tracks: albumTracks)
        } else {
            // At last track - restart current song
            print("ℹ️ At last track, restarting current song")
            seek(to: 0)
            if !isPlaying {
                play()
            }
            updateNowPlayingInfo()
        }
    }
    
    // MARK: - Playback Rate
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }
    
    // MARK: - Pitch Adjustment
    func setPitch(_ semitones: Float) {
        pitch = semitones.clamped(to: -12...12)
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
            
            // Update only time-related Now Playing info (not full metadata)
            self.updateNowPlayingTime()
            
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
    
    // MARK: - Remote Command Center
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Play command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.play()
            }
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.pause()
            }
            return .success
        }
        
        // Toggle play/pause command
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                if self.isPlaying {
                    self.pause()
                } else {
                    self.play()
                }
            }
            return .success
        }
        
        // Next track command
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.nextTrack()
            }
            return .success
        }
        
        // Previous track command
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.previousTrack()
            }
            return .success
        }
        
        // Change playback position command (scrubbing)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(to: positionEvent.positionTime)
            return .success
        }
    }
    
    private func updateRemoteCommandCenterAvailability() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let hasTrack = currentTrack != nil
        
        commandCenter.playCommand.isEnabled = hasTrack
        commandCenter.pauseCommand.isEnabled = hasTrack
        commandCenter.togglePlayPauseCommand.isEnabled = hasTrack
        
        // Always enable next/previous when there's a track
        // They can navigate to next/previous track or restart current song at boundaries
        commandCenter.nextTrackCommand.isEnabled = hasTrack
        commandCenter.previousTrackCommand.isEnabled = hasTrack
        
        commandCenter.changePlaybackPositionCommand.isEnabled = hasTrack
    }
    
    // MARK: - Now Playing Info
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            // Clear Now Playing info if no track
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            cachedArtwork = nil
            currentArtworkAlbumId = nil
            return
        }
        
        // Get existing info or create new
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        
        // Only update metadata if track/album changed (not on every time update)
        let albumId = currentAlbum?.id
        if currentArtworkAlbumId != albumId {
            // Track title
            nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
            
            // Artist/Album name
            if let album = currentAlbum {
                if let artistName = album.artist_name, !artistName.isEmpty {
                    nowPlayingInfo[MPMediaItemPropertyArtist] = artistName
                } else {
                    nowPlayingInfo[MPMediaItemPropertyArtist] = album.title
                }
                nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album.title
                
                // Load artwork if album changed
                loadArtworkForNowPlaying(albumId: album.id)
            }
            
            currentArtworkAlbumId = albumId
        }
        
        // Duration (only update if changed)
        if duration > 0 {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        }
        
        // Current time (update frequently)
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // Playback rate (update when playing state changes)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        
        // Use cached artwork if available
        if let artwork = cachedArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        // Update Now Playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        
        // Update remote command center availability
        updateRemoteCommandCenterAvailability()
    }
    
    // Update only time-related properties (called frequently)
    private func updateNowPlayingTime() {
        guard currentTrack != nil else { return }
        
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        
        // Preserve artwork if it exists
        if let artwork = cachedArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func loadArtworkForNowPlaying(albumId: UUID) {
        // Clear cached artwork when album changes
        cachedArtwork = nil
        
        guard let album = currentAlbum,
              let urlString = album.cover_art_url,
              let url = URL(string: urlString) else {
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    await MainActor.run {
                        // Only update if we're still on the same album
                        if self.currentAlbum?.id == albumId {
                            self.cachedArtwork = artwork
                            // Update Now Playing info with artwork
                            var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                        }
                    }
                }
            } catch {
                print("⚠️ Failed to load album artwork for Now Playing: \(error.localizedDescription)")
            }
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
        // If pitch is 0, we don't need the audio engine - use AVPlayer directly
        guard pitch != 0, let playerItem = playerItem else {
            // Clean up engine if pitch is back to 0
            stopAudioEngine()
            return
        }
        
        // Set up audio engine for pitch adjustment
        setupAudioEngineForPitch()
    }
    
    private func setupAudioEngineForPitch() {
        guard let playerItem = playerItem,
              let asset = playerItem.asset as? AVURLAsset else {
            return
        }
        
        // Stop existing engine
        stopAudioEngine()
        
        Task {
            do {
                // For remote URLs, we need to download the file first
                let url = asset.url
                var localURL: URL
                
                if url.isFileURL {
                    localURL = url
                } else {
                    // Download remote file to temporary location
                    let (tempURL, _) = try await URLSession.shared.download(from: url)
                    localURL = tempURL
                }
                
                // Create audio engine
                let engine = AVAudioEngine()
                let playerNode = AVAudioPlayerNode()
                let pitchNode = AVAudioUnitTimePitch()
                
                // Set pitch (semitones to cents: 1 semitone = 100 cents)
                pitchNode.pitch = pitch * 100
                
                // Attach nodes
                engine.attach(playerNode)
                engine.attach(pitchNode)
                
                // Load audio file
                let audioFile = try AVAudioFile(forReading: localURL)
                let format = audioFile.processingFormat
                
                // Connect nodes: playerNode -> pitchNode -> output
                engine.connect(playerNode, to: pitchNode, format: format)
                engine.connect(pitchNode, to: engine.mainMixerNode, format: format)
                
                // Schedule the file
                playerNode.scheduleFile(audioFile, at: nil) {
                    // Handle completion
                    Task { @MainActor in
                        if self.isLooping {
                            // If looping, reschedule
                            if let file = try? AVAudioFile(forReading: localURL) {
                                self.playerNode?.scheduleFile(file, at: nil)
                            }
                        } else {
                            self.isPlaying = false
                        }
                    }
                }
                
                // Start engine
                try engine.start()
                
                await MainActor.run {
                    self.audioEngine = engine
                    self.playerNode = playerNode
                    self.pitchNode = pitchNode
                    // Pause AVPlayer since we're using engine now
                    self.player?.pause()
                    self.isPlaying = false // Will be set to true when play() is called
                }
            } catch {
                print("⚠️ Failed to set up audio engine for pitch: \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = "Failed to apply pitch adjustment: \(error.localizedDescription)"
                    // Fall back to AVPlayer
                    self.pitch = 0
                }
            }
        }
    }
    
    private func stopAudioEngine() {
        if let playerNode = playerNode {
            playerNode.stop()
        }
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine = nil
        playerNode = nil
        pitchNode = nil
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

