import SwiftUI
import AVFoundation

struct AudioPlayerView: View {
    @ObservedObject var playerVM: AudioPlayerViewModel
    let track: StudioTrackRecord
    
    init(track: StudioTrackRecord) {
        self.track = track
        self.playerVM = AudioPlayerViewModel.shared
    }
    
    @State private var showControls = false
    @State private var showPitchControls = false
    @State private var showLoopControls = false
    @State private var showTrimControls = false
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color(red: 0.1, green: 0.1, blue: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Album Art / Placeholder
                    albumArtView
                        .padding(.top, 40)
                        .padding(.bottom, 40)
                    
                    // Track Info
                    trackInfoView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    
                    // Progress Bar
                    progressView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    
                    // Main Playback Controls
                    mainControlsView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    
                    // Secondary Controls
                    secondaryControlsView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    
                    // Advanced Controls (Collapsible)
                    if showControls {
                        advancedControlsView
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            
            // Loading Overlay
            if playerVM.isLoading {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Loading track...")
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                }
            }
            
            // Error Overlay
            if let error = playerVM.errorMessage {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.white)
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 100)
                }
            }
        }
        .onAppear {
            // Track is already loaded if coming from bottom player bar
            // Only load if it's a different track
            if playerVM.currentTrack?.id != track.id {
                playerVM.loadTrack(track)
            }
        }
    }
    
    // MARK: - Album Art View
    private var albumArtView: some View {
        Group {
            if let album = playerVM.currentAlbum,
               let urlString = album.cover_art_url,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        albumPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        albumPlaceholder
                    @unknown default:
                        albumPlaceholder
                    }
                }
            } else {
                albumPlaceholder
            }
        }
        .frame(width: 280, height: 280)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
    }
    
    private var albumPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "music.note")
                .font(.system(size: 80))
                .foregroundColor(.white.opacity(0.3))
        }
    }
    
    // MARK: - Track Info View
    private var trackInfoView: some View {
        VStack(spacing: 8) {
            Text(track.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            if let trackNumber = track.track_number {
                Text("Track \(trackNumber)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    // MARK: - Progress View
    private var progressView: some View {
        VStack(spacing: 8) {
            // Progress Slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    // Progress track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(
                            width: progressWidth(geometry: geometry),
                            height: 4
                        )
                    
                    // Draggable thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .offset(x: progressWidth(geometry: geometry) - 6)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDragging = true
                                    let newTime = Double(value.location.x / geometry.size.width) * playerVM.duration
                                    playerVM.seek(to: max(0, min(newTime, playerVM.duration)))
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                }
            }
            .frame(height: 44)
            
            // Time Labels
            HStack {
                Text(formatTime(playerVM.currentTime))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
                
                Spacer()
                
                Text(formatTime(playerVM.duration))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
            }
        }
    }
    
    private func progressWidth(geometry: GeometryProxy) -> CGFloat {
        guard playerVM.duration > 0, playerVM.duration.isFinite else { return 0 }
        let progress = playerVM.currentTime / playerVM.duration
        return min(geometry.size.width * CGFloat(progress), geometry.size.width)
    }
    
    // MARK: - Main Controls View
    private var mainControlsView: some View {
        HStack(spacing: 40) {
            // Rewind 15s
            Button {
                playerVM.seek(to: max(0, playerVM.currentTime - 15))
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            
            // Play/Pause
            Button {
                if playerVM.isPlaying {
                    playerVM.pause()
                } else {
                    playerVM.play()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.black)
                        .offset(x: playerVM.isPlaying ? 0 : 2)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            
            // Forward 15s
            Button {
                playerVM.seek(to: min(playerVM.duration, playerVM.currentTime + 15))
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Secondary Controls View
    private var secondaryControlsView: some View {
        HStack(spacing: 32) {
            // Playback Rate
            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                    Button {
                        playerVM.setPlaybackRate(Float(rate))
                    } label: {
                        HStack {
                            Text("\(rate, specifier: "%.2f")x")
                            if abs(playerVM.playbackRate - Float(rate)) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 20))
                    Text("\(playerVM.playbackRate, specifier: "%.2f")x")
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 60)
            }
            
            // Loop
            Button {
                playerVM.toggleLoop()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: playerVM.isLooping ? "repeat.circle.fill" : "repeat.circle")
                        .font(.system(size: 20))
                    Text("Loop")
                        .font(.caption2)
                }
                .foregroundColor(playerVM.isLooping ? .white : .white.opacity(0.8))
                .frame(width: 60)
            }
            
            // Pitch
            Button {
                showPitchControls.toggle()
                showLoopControls = false
                showTrimControls = false
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                    Text("Pitch")
                        .font(.caption2)
                }
                .foregroundColor(showPitchControls ? .white : .white.opacity(0.8))
                .frame(width: 60)
            }
            
            // Trim
            Button {
                showTrimControls.toggle()
                showPitchControls = false
                showLoopControls = false
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "scissors")
                        .font(.system(size: 20))
                    Text("Trim")
                        .font(.caption2)
                }
                .foregroundColor(showTrimControls ? .white : .white.opacity(0.8))
                .frame(width: 60)
            }
        }
    }
    
    // MARK: - Advanced Controls View
    private var advancedControlsView: some View {
        VStack(spacing: 20) {
            // Pitch Controls
            if showPitchControls {
                pitchControlView
            }
            
            // Loop Controls
            if showLoopControls {
                loopControlView
            }
            
            // Trim Controls
            if showTrimControls {
                TrimTrackView(playerVM: playerVM, track: track)
            }
        }
        .animation(.easeInOut, value: showPitchControls)
        .animation(.easeInOut, value: showLoopControls)
        .animation(.easeInOut, value: showTrimControls)
    }
    
    // MARK: - Pitch Control View
    private var pitchControlView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Pitch Adjustment")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(playerVM.pitch)) semitones")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack {
                Text("-12")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                
                Slider(
                    value: Binding(
                        get: { playerVM.pitch },
                        set: { playerVM.setPitch($0) }
                    ),
                    in: -12...12,
                    step: 1
                )
                .tint(.white)
                
                Text("+12")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Loop Control View
    private var loopControlView: some View {
        VStack(spacing: 16) {
            Toggle("Enable Loop", isOn: $playerVM.isLooping)
                .tint(.white)
                .foregroundColor(.white)
            
            if playerVM.isLooping {
                VStack(spacing: 12) {
                    HStack {
                        Text("Start:")
                            .foregroundColor(.white.opacity(0.7))
                        TextField("0", value: $playerVM.loopStart, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                    }
                    
                    HStack {
                        Text("End:")
                            .foregroundColor(.white.opacity(0.7))
                        TextField("0", value: $playerVM.loopEnd, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Helper Methods
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else {
            return "0:00"
        }
        
        let validTime = max(0, time)
        let minutes = Int(validTime) / 60
        let seconds = Int(validTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Trim Track View
struct TrimTrackView: View {
    @ObservedObject var playerVM: AudioPlayerViewModel
    let track: StudioTrackRecord
    
    @State private var trimStart: TimeInterval = 0
    @State private var trimEnd: TimeInterval = 0
    @State private var isTrimming = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Trim Track")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    TextField("0", value: $trimStart, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("End")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    TextField("0", value: $trimEnd, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            if showSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Trimmed version saved!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Button {
                Task {
                    await trimTrack()
                }
            } label: {
                if isTrimming {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Trim & Save")
                        .font(.headline)
                        .foregroundColor(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .disabled(isTrimming || trimStart >= trimEnd)
        }
        .padding(20)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
        .onAppear {
            trimStart = 0
            trimEnd = playerVM.duration.isFinite && !playerVM.duration.isNaN ? playerVM.duration : 0
        }
    }
    
    private func trimTrack() async {
        isTrimming = true
        errorMessage = nil
        showSuccess = false
        
        do {
            guard let trimmedData = try await playerVM.trimTrack(startTime: trimStart, endTime: trimEnd) else {
                errorMessage = "Failed to trim track"
                isTrimming = false
                return
            }
            
            let versionService = VersionService.shared
            _ = try await versionService.createTrackVersion(
                for: track,
                audioData: trimmedData,
                notes: "Trimmed: \(formatTime(trimStart)) - \(formatTime(trimEnd))",
                duration: trimEnd - trimStart
            )
            
            isTrimming = false
            showSuccess = true
            
            // Hide success message after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            showSuccess = false
        } catch {
            errorMessage = error.localizedDescription
            isTrimming = false
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else {
            return "0:00"
        }
        
        let validTime = max(0, time)
        let minutes = Int(validTime) / 60
        let seconds = Int(validTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

