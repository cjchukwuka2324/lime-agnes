import SwiftUI
import AVFoundation
import Combine

struct AudioPlayerView: View {
    @ObservedObject var playerVM: AudioPlayerViewModel
    let track: StudioTrackRecord
    @Environment(\.dismiss) private var dismiss
    
    init(track: StudioTrackRecord) {
        self.track = track
        self.playerVM = AudioPlayerViewModel.shared
    }
    
    @State private var showControls = false
    @State private var isDragging = false
    @State private var comments: [TrackComment] = []
    @State private var selectedTimestamp: Double?
    @State private var commentText: String = ""
    @State private var isLoadingComments = false
    @State private var commentError: String?
    @State private var showCommentsView = false
    @FocusState private var isCommentFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background - solid black
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Fixed header row with dismiss button (doesn't scroll)
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .frame(height: 44)
                    .background(Color.black)
                    
                    // ScrollView starts below the fixed header
                    ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Album Art / Placeholder
                        albumArtView
                            .padding(.top, 20)
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
                        
                        // Spacer to push content up and provide scroll target
                        Spacer()
                            .frame(height: 20)
                            .id("scrollBottom")
                    }
                }
                .onChange(of: isCommentFocused) { _, isFocused in
                    if isFocused {
                        // Automatically select current playback time when comment box is tapped
                        // Always update to current time, even if a timestamp was previously selected
                        selectedTimestamp = playerVM.currentTime
                        print("🕐 Timestamp auto-selected on comment box tap: \(playerVM.currentTime)s")
                        
                        // Scroll to bottom immediately when field is focused
                        // This happens before keyboard animation starts
                        DispatchQueue.main.async {
                            // Scroll without animation for instant positioning
                            proxy.scrollTo("scrollBottom", anchor: .bottom)
                        }
                    } else {
                        // Clear selected timestamp when keyboard is dismissed
                        selectedTimestamp = nil
                        print("🕐 Timestamp cleared on keyboard dismiss")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                    // Scroll when keyboard notification fires (happens before keyboard animation)
                    // This ensures we're scrolled before the keyboard covers content
                    if isCommentFocused {
                        DispatchQueue.main.async {
                            proxy.scrollTo("scrollBottom", anchor: .bottom)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    commentInputView
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0.8), Color.clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                            .ignoresSafeArea(edges: .bottom)
                        )
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
            
            // Comment Error Overlay
            if let error = commentError {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.white)
                            .font(.subheadline)
                        Button {
                            commentError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 100)
                }
            }
        }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.navigationStack)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(false)
        .onAppear {
            // Ensure navigation bar is visible
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .black
            appearance.shadowColor = .clear
            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
            
            // Track is already loaded if coming from bottom player bar
            // Only load if it's a different track
            if playerVM.currentTrack?.id != track.id {
                playerVM.loadTrack(track)
            }
            
            // Load comments
            Task {
                await loadComments()
            }
        }
        .onChange(of: track.id) { _ in
            // Reload comments when track changes
            Task {
                await loadComments()
            }
        }
        .sheet(isPresented: $showCommentsView) {
            TrackCommentsView(
                track: track,
                comments: $comments,
                playerVM: playerVM
            )
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
                                .onEnded { value in
                                    isDragging = false
                                    // Automatically select the timestamp where dragging stopped
                                    let finalTime = Double(value.location.x / geometry.size.width) * playerVM.duration
                                    let clampedTime = max(0, min(finalTime, playerVM.duration))
                                    selectedTimestamp = clampedTime
                                    print("🕐 Timestamp auto-selected after drag: \(clampedTime)s")
                                }
                        )
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Set comment timestamp as user drags
                            let progress = max(0, min(1, Double(value.location.x / geometry.size.width)))
                            let timestamp = progress * playerVM.duration
                            selectedTimestamp = timestamp
                        }
                        .onEnded { value in
                            // Finalize timestamp on drag end
                            let progress = max(0, min(1, Double(value.location.x / geometry.size.width)))
                            let timestamp = progress * playerVM.duration
                            print("🕐 Comment timestamp set via drag: \(timestamp)s")
                            selectedTimestamp = timestamp
                        }
                )
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
            // Previous Track
            Button {
                playerVM.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            
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
            
            // Next Track
            Button {
                playerVM.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Secondary Controls View
    private var secondaryControlsView: some View {
        // Removed all secondary controls for now
        EmptyView()
    }
    
    // MARK: - Advanced Controls View
    private var advancedControlsView: some View {
        // Removed loop, pitch, and trim controls
        EmptyView()
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
            Toggle("Enable Loop", isOn: Binding(
                get: { playerVM.isLooping },
                set: { newValue in
                    playerVM.isLooping = newValue
                    if newValue && playerVM.loopEnd == 0 {
                        playerVM.loopEnd = playerVM.duration
                    }
                }
            ))
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
    
    // MARK: - Comment Input View
    private var commentInputView: some View {
        VStack(spacing: 8) {
            // Timestamp indicator
            if let timestamp = selectedTimestamp {
                HStack {
                    Text("Comment at \(formatTime(timestamp))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Button {
                        selectedTimestamp = nil
                        commentText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            } else {
                // Show current time as option
                HStack {
                    Text("Drag progress bar or use current time")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()
                    Button {
                        let currentTime = playerVM.currentTime
                        print("🕐 Button tapped - Setting timestamp to current time: \(currentTime)")
                        selectedTimestamp = currentTime
                        // Force UI update
                        DispatchQueue.main.async {
                            print("🕐 selectedTimestamp after update: \(selectedTimestamp?.description ?? "nil")")
                        }
                    } label: {
                        Text("Use \(formatTime(playerVM.currentTime))")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            HStack(spacing: 8) {
                // Text field
                TextField("Drop a comment...", text: $commentText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                    .foregroundColor(.white)
                    .focused($isCommentFocused)
                    .lineLimit(1...3)
                    .onSubmit {
                        if canPostComment {
                            Task { await submitComment(text: commentText) }
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                
                // View Comments button
                Button {
                    isCommentFocused = false // Dismiss keyboard first
                    showCommentsView = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 16, weight: .semibold))
                        if !comments.isEmpty {
                            Text("\(comments.count)")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white)
                    )
                }
                
                // Post button
                Button {
                    print("📤 Post button tapped")
                    print("   commentText: '\(commentText)'")
                    print("   selectedTimestamp: \(selectedTimestamp?.description ?? "nil")")
                    print("   canPostComment: \(canPostComment)")
                    
                    guard canPostComment else {
                        print("❌ Cannot post - button should be disabled")
                        return
                    }
                    
                    Task {
                        await submitComment(text: commentText)
                    }
                } label: {
                    Text("Post")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(canPostComment ? .black : .white.opacity(0.5))
                        .frame(width: 56, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(canPostComment ? Color.white : Color.white.opacity(0.2))
                        )
                }
                .disabled(!canPostComment)
            }
            
            // Dismiss keyboard button (shown when keyboard is visible)
            if isCommentFocused {
                Button {
                    isCommentFocused = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "keyboard.chevron.compact.down")
                        Text("Dismiss Keyboard")
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 6)
                }
            }
        }
    }
    
    private var canPostComment: Bool {
        let hasText = !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTimestamp = selectedTimestamp != nil
        let result = hasText && hasTimestamp
        
        // Debug when state changes
        if hasText && hasTimestamp {
            print("✅ canPostComment = true (text: '\(commentText)', timestamp: \(selectedTimestamp!))")
        }
        
        return result
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
    
    // MARK: - Comments Loading
    private func loadComments() async {
        isLoadingComments = true
        defer { isLoadingComments = false }
        
        do {
            comments = try await TrackCommentService.shared.getComments(for: track.id)
        } catch {
            print("⚠️ Failed to load comments: \(error.localizedDescription)")
            commentError = "Failed to load comments"
        }
    }
    
    private func submitComment(text: String) async {
        // Validate timestamp
        guard let timestamp = selectedTimestamp else {
            await MainActor.run {
                commentError = "Please select a timestamp for your comment"
            }
            return
        }
        
        // Validate text
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            await MainActor.run {
                commentError = "Comment cannot be empty"
            }
            return
        }
        
        // Clear any previous errors
        await MainActor.run {
            commentError = nil
        }
        
        do {
            print("📝 Posting comment at \(timestamp)s: \(trimmedText)")
            let newComment = try await TrackCommentService.shared.createComment(
                trackId: track.id,
                content: trimmedText,
                timestamp: timestamp
            )
            
            print("✅ Comment posted successfully: \(newComment.id)")
            
            // Add to local comments array and reset state
            await MainActor.run {
                comments.append(newComment)
                comments.sort { $0.timestamp < $1.timestamp }
                
                // Reset state to allow posting another comment
                commentText = ""
                selectedTimestamp = nil
                commentError = nil
                isCommentFocused = false // Dismiss keyboard after posting
            }
        } catch {
            print("❌ Error posting comment: \(error)")
            print("   Error details: \(error.localizedDescription)")
            await MainActor.run {
                commentError = "Failed to post comment: \(error.localizedDescription)"
            }
        }
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

