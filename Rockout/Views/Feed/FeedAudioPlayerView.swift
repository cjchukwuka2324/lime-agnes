import SwiftUI
import AVFoundation

struct FeedAudioPlayerView: View {
    let audioURL: URL
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var duration: TimeInterval = 0
    @State private var currentTime: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Play/Pause Button
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(Color(hex: "#1ED760"))
                }
                
                // Mute/Unmute Button
                Button {
                    isMuted.toggle()
                    player?.volume = isMuted ? 0.0 : 1.0
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // Waveform Icon
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 24)
                
                // Progress
                VStack(alignment: .leading, spacing: 4) {
                    let safeDuration = (duration.isFinite && !duration.isNaN) ? max(1, duration) : 1
                    let safeCurrentTime = (currentTime.isFinite && !currentTime.isNaN) ? max(0, min(currentTime, safeDuration)) : 0
                    
                    Slider(value: Binding(
                        get: { safeCurrentTime },
                        set: { newValue in
                            let clampedValue = max(0, min(newValue, safeDuration))
                            if clampedValue.isFinite && !clampedValue.isNaN {
                                currentTime = clampedValue
                                player?.currentTime = clampedValue
                            }
                        }
                    ), in: 0...safeDuration)
                    .tint(Color(hex: "#1ED760"))
                    
                    HStack {
                        Text(formatTime(safeCurrentTime))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text(formatTime(safeDuration))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            setupAudioPlayer()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func setupAudioPlayer() {
        // Check if URL is valid
        guard audioURL.scheme != nil else {
            print("Failed to load audio: Invalid URL scheme")
            duration = 0
            return
        }
        
        // For remote URLs, we need to download first or use AVPlayer
        if audioURL.isFileURL {
            setupLocalAudio()
        } else {
            setupRemoteAudio()
        }
    }
    
    private func setupLocalAudio() {
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            
                        // Load audio player from local file
            player = try AVAudioPlayer(contentsOf: audioURL)
            player?.prepareToPlay()
            player?.volume = isMuted ? 0.0 : 1.0
            let playerDuration = player?.duration ?? 0
            // Validate duration is finite and not NaN
            duration = (playerDuration.isFinite && !playerDuration.isNaN) ? max(0, playerDuration) : 0
        } catch {
            print("Failed to load audio: \(error.localizedDescription)")
            duration = 0
        }
    }
    
    private func setupRemoteAudio() {
        // For remote URLs, download first or use AVPlayer/AVAsset
        Task {
            do {
                // Download audio data
                let (data, _) = try await URLSession.shared.data(from: audioURL)
                
                // Save to temporary file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("m4a")
                
                try data.write(to: tempURL)
                
                await MainActor.run {
                    do {
                        // Configure audio session
                        let audioSession = AVAudioSession.sharedInstance()
                        try audioSession.setCategory(.playback, mode: .default, options: [])
                        try audioSession.setActive(true)
                        
                        // Load audio player from temporary file
                        player = try AVAudioPlayer(contentsOf: tempURL)
                        player?.prepareToPlay()
                        player?.volume = isMuted ? 0.0 : 1.0
                        let playerDuration = player?.duration ?? 0
                        // Validate duration is finite and not NaN
                        duration = (playerDuration.isFinite && !playerDuration.isNaN) ? max(0, playerDuration) : 0
                    } catch {
                        print("Failed to load audio: \(error.localizedDescription)")
                        duration = 0
                    }
                }
            } catch {
                print("Failed to download audio: \(error.localizedDescription)")
                await MainActor.run {
                    duration = 0
                }
            }
        }
    }
    
    private func togglePlayback() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            timer?.invalidate()
        } else {
            player.play()
            startTimer()
        }
        isPlaying.toggle()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let playerTime = player?.currentTime ?? 0
            // Validate time values are finite and not NaN
            if playerTime.isFinite && !playerTime.isNaN {
                let safeDuration = (duration.isFinite && !duration.isNaN) ? duration : 1
                currentTime = max(0, min(playerTime, safeDuration))
                
                if currentTime >= safeDuration {
                    isPlaying = false
                    timer?.invalidate()
                    currentTime = 0
                }
            } else {
                currentTime = 0
            }
        }
    }
    
    private func cleanup() {
        player?.stop()
        timer?.invalidate()
        player = nil
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        // Validate time is finite and not NaN
        guard time.isFinite && !time.isNaN else {
            return "0:00"
        }
        let safeTime = max(0, time)
        let minutes = Int(safeTime) / 60
        let seconds = Int(safeTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
