import SwiftUI
import AVFoundation

struct VoiceRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onRecordingComplete: (URL?) -> Void
    
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingDuration: TimeInterval = 0
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackTime: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var scrubberValue: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var playbackTimer: Timer?
    @State private var errorMessage: String?
    @State private var didConfirmRecording = false
    
    private let maxRecordingDuration: TimeInterval = 60.0 // 1 minute
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Timer display
                    timerDisplay
                    
                    // Record/Stop button (only show when recording or no recording exists)
                    if isRecording || recordingURL == nil {
                        recordButton
                            .padding(.top, 20)
                    }
                    
                    // Playback controls (shown after recording)
                    if let recordingURL = recordingURL, !isRecording {
                        playbackControls
                            .padding(.top, 20)
                    }
                    
                    // Action buttons
                    actionButtons
                        .padding(.top, 30)
                    
                    Spacer()
                }
                .padding(.vertical, 40)
                
                // Error message overlay
                if let errorMessage = errorMessage {
                    VStack {
                        Spacer()
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(8)
                            .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Voice Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        cleanup()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                // Pre-warm audio session for faster first recording
                Task {
                    await prepareAudioSession()
                }
            }
            .onDisappear {
                cleanup()
            }
        }
    }
    
    // MARK: - UI Components
    
    private var timerDisplay: some View {
        let displayTime: TimeInterval
        if isRecording {
            displayTime = recordingTime
        } else if isPlaying || playbackTime > 0 {
            displayTime = playbackTime
        } else if recordingDuration > 0 {
            displayTime = recordingDuration
        } else {
            displayTime = 0
        }
        
        return Text(formatTime(displayTime))
            .font(.system(size: 48, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
    }
    
    private var recordButton: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                Task {
                    await startRecording()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color(hex: "#1ED760"))
                    .frame(width: 80, height: 80)
                
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
        }
    }
    
    private var playbackControls: some View {
        VStack(spacing: 15) {
            scrubber
            
            // Play/Pause button
            Button {
                if isPlaying {
                    pausePlayback()
                } else {
                    playRecording()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color(hex: "#1ED760"))
            }
        }
    }
    
    private var scrubber: some View {
        let duration = audioPlayer?.duration ?? recordingDuration
        return VStack(spacing: 8) {
            Slider(value: Binding(
                get: { isScrubbing ? scrubberValue : playbackTime },
                set: { newValue in
                    scrubberValue = newValue
                    if isScrubbing {
                        playbackTime = newValue
                    }
                }
            ), in: 0...(duration > 0 ? duration : 1), onEditingChanged: { editing in
                isScrubbing = editing
                if !editing {
                    seekToTime(scrubberValue)
                }
            })
            .disabled(duration <= 0)
            .tint(Color(hex: "#1ED760"))
            
            HStack {
                Text(formatTime(isScrubbing ? scrubberValue : playbackTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.7))
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 20) {
            // Delete button
            if recordingURL != nil {
                Button {
                    deleteRecording()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.title3)
                        Text("Delete")
                            .font(.caption)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.15))
                    )
                }
            }
            
            // Re-record button
            if recordingURL != nil {
                Button {
                    reRecord()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                        Text("Re-record")
                            .font(.caption)
                    }
                    .foregroundColor(Color(hex: "#1ED760"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#1ED760").opacity(0.15))
                    )
                }
            }
            
            // Use Recording button
            if recordingURL != nil {
                Button {
                    confirmRecording()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.title3)
                        Text("Use Recording")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#1ED760"))
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Recording Functions
    
    private func prepareAudioSession() async {
        // Pre-warm audio session by checking permission and setting up category
        // This makes the first recording start faster
        let hasPermission = await requestPermission()
        guard hasPermission else {
            return
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set category but don't activate yet (activation happens when recording starts)
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
        } catch {
            // Silently fail - will retry when recording starts
        }
    }
    
    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    
    private func startRecording() async {
        // 1. Check microphone permission
        let hasPermission = await requestPermission()
        guard hasPermission else {
            await MainActor.run {
                errorMessage = "Microphone permission denied. Please enable microphone access in Settings."
            }
            return
        }
        
        // 2. Handle audio player conflicts
        let audioPlayer = AudioPlayerViewModel.shared
        if audioPlayer.isPlaying {
            await MainActor.run {
                audioPlayer.pause()
            }
            // Wait for audio player to release the session
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // Post notification to allow other components to respond
        NotificationCenter.default.post(name: NSNotification.Name("VoiceRecorderWillStart"), object: nil)
        
        // Wait a moment for other components to respond
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // 3. Setup audio session with proper sequencing
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // First, deactivate any existing session
            do {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                // May not be active, that's okay
            }
            
            // Wait for deactivation to complete
            try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            // Set category BEFORE activating
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [])
            
            // Small delay before activation
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            // Activate the session
            try audioSession.setActive(true)
        } catch {
            await MainActor.run {
                errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
            }
            return
        }
        
        // 4. Prepare recording file and settings
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("voice_recording_\(UUID().uuidString).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        // 5. Update UI state BEFORE starting recording (fixes timing issue)
        await MainActor.run {
            isRecording = true
            recordingTime = 0
            errorMessage = nil
        }
        
        // 6. Create recorder and start recording
        do {
            let recorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            recorder.isMeteringEnabled = true
            
            await MainActor.run {
                audioRecorder = recorder
                recordingURL = audioFilename
            }
            
            // Start recording
            recorder.record()
            
            // Start recording timer
            await MainActor.run {
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                    if self.isRecording {
                        self.recordingTime += 0.1
                        
                        // Stop at max duration
                        if self.recordingTime >= self.maxRecordingDuration {
                            self.stopRecording()
                        }
                    } else {
                        timer.invalidate()
                    }
                }
            }
        } catch {
            await MainActor.run {
                isRecording = false
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
            }
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        if let recorder = audioRecorder {
            recordingURL = recorder.url
        }
        
        audioRecorder = nil
        
        // Capture actual file duration for accurate playback progress
        if let url = recordingURL {
            let asset = AVURLAsset(url: url)
            recordingDuration = asset.duration.seconds
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    // MARK: - Playback Functions
    
    private func playRecording() {
        guard let url = recordingURL else { return }
        
        // If we already have a player (paused), resume instead of recreating
        if let player = audioPlayer {
            player.play()
            isPlaying = true
            
            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                guard let player = self.audioPlayer else {
                    timer.invalidate()
                    return
                }
                if self.isPlaying {
                    self.playbackTime = player.currentTime
                    if !self.isScrubbing { self.scrubberValue = self.playbackTime }
                    let duration = player.duration > 0 ? player.duration : self.recordingDuration
                    if duration > 0, self.playbackTime >= duration {
                        self.playbackFinished()
                    }
                } else {
                    timer.invalidate()
                }
            }
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = PlaybackDelegate(
                onFinish: {
                    self.playbackFinished()
                }
            )
            
            // Set duration reference if needed
            if recordingDuration == 0 {
                recordingDuration = audioPlayer?.duration ?? 0
            }
            
            if playbackTime > 0 {
                audioPlayer?.currentTime = playbackTime
            }
            
            audioPlayer?.play()
            isPlaying = true
            
            // Start playback timer
            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                guard let player = self.audioPlayer else {
                    timer.invalidate()
                    return
                }
                if self.isPlaying {
                    self.playbackTime = player.currentTime
                    if !self.isScrubbing { self.scrubberValue = self.playbackTime }
                    let duration = player.duration > 0 ? player.duration : self.recordingDuration
                    if duration > 0, self.playbackTime >= duration {
                        self.playbackFinished()
                    }
                } else {
                    timer.invalidate()
                }
            }
        } catch {
            errorMessage = "Failed to play recording: \(error.localizedDescription)"
        }
    }
    
    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    private func seekToTime(_ time: TimeInterval) {
        let duration = audioPlayer?.duration ?? recordingDuration
        let clamped: TimeInterval
        if duration > 0 {
            clamped = max(0, min(time, duration))
        } else {
            clamped = max(0, time)
        }
        audioPlayer?.currentTime = clamped
        playbackTime = clamped
        scrubberValue = clamped
    }
    
    private func playbackFinished() {
        isPlaying = false
        playbackTime = 0
        scrubberValue = 0
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
    
    // MARK: - Action Functions
    
    private func deleteRecording() {
        stopPlayback()
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        recordingTime = 0
        recordingDuration = 0
        playbackTime = 0
        scrubberValue = 0
        isScrubbing = false
    }
    
    private func reRecord() {
        deleteRecording()
        // Just clear the recording - user will need to press record button again
    }
    
    private func confirmRecording() {
        // Stop recording/playback but DO NOT delete the file
        stopRecording()
        stopPlayback()
        didConfirmRecording = true
        onRecordingComplete(recordingURL)
        dismiss()
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        stopRecording()
        stopPlayback()
        
        // Clean up temporary file only if the user did not confirm
        if !didConfirmRecording, let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
        playbackTime = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer = nil
    }
    
    // MARK: - Helper Functions
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Playback Delegate

private class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
