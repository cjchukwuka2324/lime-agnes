import SwiftUI
import AVFoundation
import AVKit
import PhotosUI

struct PostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let service: FeedService
    let leaderboardEntry: LeaderboardEntrySummary?
    let parentPost: Post?
    let prefilledText: String?
    let onPostCreated: (() -> Void)?
    
    @State private var text: String
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var selectedImages: [UIImage] = [] // Up to 5 images
    @State private var selectedVideo: URL?
    @State private var audioRecordingURL: URL?
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var isUploadingMedia = false
    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    @State private var showImageCrop = false
    @State private var imageToCrop: UIImage?
    @State private var showVideoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var spotifyLink: SpotifyLink?
    @State private var poll: Poll?
    @State private var backgroundMusic: BackgroundMusic?
    @State private var showSpotifyLinkAdd = false
    @State private var showPollCreation = false
    @State private var showBackgroundMusicSelector = false
    
    private let imageService = FeedImageService.shared
    private let mediaService = FeedMediaService.shared
    
    init(
        service: FeedService = SupabaseFeedService.shared as FeedService,
        leaderboardEntry: LeaderboardEntrySummary? = nil,
        parentPost: Post? = nil,
        prefilledText: String? = nil,
        onPostCreated: (() -> Void)? = nil
    ) {
        self.service = service
        self.leaderboardEntry = leaderboardEntry
        self.parentPost = parentPost
        self.prefilledText = prefilledText
        self.onPostCreated = onPostCreated
        self._text = State(initialValue: prefilledText ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                ScrollView {
                    contentView
                }
            }
            .navigationTitle(parentPost == nil ? "New Post" : "Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await post()
                        }
                    } label: {
                        if isPosting || isUploadingMedia {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Post")
                                .fontWeight(.semibold)
                                .foregroundColor(canPost ? .white : .gray)
                        }
                    }
                    .disabled(!canPost || isPosting || isUploadingMedia || isRecording)
                }
            }
            .photosPicker(
                isPresented: $showImagePicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 4,
                matching: .images
            )
            .sheet(isPresented: $showImageCrop) {
                if let image = imageToCrop {
                    ImageCropView(image: Binding(
                        get: { image },
                        set: { newImage in
                            if let newImage = newImage, let index = selectedImages.firstIndex(where: { $0 === image }) {
                                selectedImages[index] = newImage
                            }
                        }
                    ))
                }
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPicker(selectedVideoURL: $selectedVideo)
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraPickerView(
                    selectedImages: $selectedImages,
                    selectedVideo: $selectedVideo
                )
            }
            .sheet(isPresented: $showSpotifyLinkAdd) {
                SpotifyLinkAddView(selectedSpotifyLink: $spotifyLink)
            }
            .sheet(isPresented: $showPollCreation) {
                PollCreationView(poll: $poll)
            }
            .sheet(isPresented: $showBackgroundMusicSelector) {
                BackgroundMusicSelectorView(selectedBackgroundMusic: $backgroundMusic)
            }
            .onChange(of: backgroundMusic) { oldValue, newValue in
                if let newValue = newValue {
                    print("🎵 PostComposerView: backgroundMusic changed to: \(newValue.name) by \(newValue.artist)")
                } else {
                    print("🎵 PostComposerView: backgroundMusic cleared")
                }
            }
            .onChange(of: selectedVideo) { _, newVideoURL in
                if let videoURL = newVideoURL {
                    Task {
                        await validateVideoDuration(videoURL)
                    }
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task {
                    await loadImagesFromPicker(newItems)
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "#050505"),
                Color(hex: "#0C7C38"),
                Color(hex: "#1DB954"),
                Color(hex: "#1ED760"),
                Color(hex: "#050505")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private var contentView: some View {
        VStack(spacing: 20) {
            if let entry = leaderboardEntry {
                leaderboardPreview(entry: entry)
            }
            
            if !selectedImages.isEmpty {
                imagesPreview(images: selectedImages)
            }
            
            if let selectedVideo = selectedVideo {
                videoPreview(videoURL: selectedVideo)
            }
            
            if let audioRecordingURL = audioRecordingURL {
                audioPreview(audioURL: audioRecordingURL)
            }
            
            if let spotifyLink = spotifyLink {
                spotifyLinkPreview(link: spotifyLink)
            }
            
            if let poll = poll {
                pollPreview(poll: poll)
            }
            
            if let backgroundMusic = backgroundMusic {
                backgroundMusicPreview(music: backgroundMusic)
            }
            
            textEditorView
            mediaButtonsRow
            errorMessageView
            Spacer()
        }
        .padding(20)
    }
    
    private func leaderboardPreview(entry: LeaderboardEntrySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sharing")
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.7))
            
            LeaderboardAttachmentView(entry: entry)
        }
        .padding(.top, 20)
    }
    
    private func imagesPreview(images: [UIImage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photos (\(images.count)/4)")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                if images.count < 4 {
                    Button {
                        showImagePicker = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color(hex: "#1ED760"))
                    }
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            Button {
                                selectedImages.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .padding(4)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    private func videoPreview(videoURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Video")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button {
                    self.selectedVideo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.7))
                Text(videoURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
    }
    
    private func audioPreview(audioURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Voice Recording")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button {
                    self.audioRecordingURL = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            HStack {
                Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundColor(Color(hex: "#1ED760"))
                Text(formatTime(recordingTime))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                Text("/ 1:00")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
    }
    
    private var textEditorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(parentPost == nil ? "What's on your mind?" : "Write a reply")
                .font(.headline)
                .foregroundColor(.white)
            
            TextEditor(text: $text)
                .font(.body)
                .foregroundColor(.white)
                .frame(minHeight: 120)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .scrollContentBackground(.hidden)
        }
    }
    
    private var mediaButtonsRow: some View {
        HStack(spacing: 12) {
            cameraButton
            voiceButton
            musicButton
            pollButton
            if !selectedImages.isEmpty {
                backgroundMusicButton
            }
        }
        .padding(.vertical, 8)
    }
    
    private var cameraButton: some View {
        Menu {
            Button {
                showCameraPicker = true
            } label: {
                Label("Take Photo/Video", systemImage: "camera")
            }
            
        Button {
            showImagePicker = true
            } label: {
                Label("Choose from Gallery", systemImage: "photo.on.rectangle")
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "camera.fill")
                    .font(.title3)
                Text("Photo")
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.15))
            )
        }
        .disabled(isPosting || isUploadingMedia || isRecording)
    }
    
    private var voiceButton: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.fill")
                    .font(.title3)
                Text(isRecording ? formatTime(recordingTime) + "/1:00" : "Voice")
                    .font(.caption2)
            }
            .foregroundColor(isRecording ? Color.red : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isRecording ? Color.red.opacity(0.2) : Color.white.opacity(0.15))
            )
        }
        .disabled(isPosting || isUploadingMedia || !selectedImages.isEmpty || selectedVideo != nil)
    }
    
    private var musicButton: some View {
        Button {
            showSpotifyLinkAdd = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.title3)
                Text("Music")
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.15))
            )
        }
        .disabled(isPosting || isUploadingMedia || isRecording)
    }
    
    private var pollButton: some View {
        Button {
            showPollCreation = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "chart.bar")
                    .font(.title3)
                Text("Poll")
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.15))
            )
        }
        .disabled(isPosting || isUploadingMedia || isRecording)
    }
    
    private var backgroundMusicButton: some View {
        Button {
            showBackgroundMusicSelector = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "music.mic")
                    .font(.title3)
                Text("BG Music")
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.15))
            )
        }
        .disabled(isPosting || isUploadingMedia || isRecording)
    }
    
    // MARK: - Preview Sections
    
    private func spotifyLinkPreview(link: SpotifyLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spotify Link")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button {
                    spotifyLink = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            SpotifyLinkCardView(spotifyLink: link)
        }
    }
    
    private func pollPreview(poll: Poll) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            pollPreviewHeader
            pollPreviewContent(poll: poll)
        }
    }
    
    private var pollPreviewHeader: some View {
            HStack {
                Text("Poll")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button {
                    self.poll = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
            }
                }
            }
            
    private func pollPreviewContent(poll: Poll) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(poll.question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                
                ForEach(Array(poll.options.enumerated()), id: \.element.id) { index, option in
                pollOptionRow(option: option, pollType: poll.type)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
    
    private func pollOptionRow(option: PollOption, pollType: String) -> some View {
        HStack {
            Image(systemName: pollType == "single" ? "circle" : "square")
            Text(option.text)
        }
        .font(.caption)
        .foregroundColor(.white.opacity(0.8))
    }
    
    private func backgroundMusicPreview(music: BackgroundMusic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Background Music")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button {
                    backgroundMusic = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            HStack(spacing: 12) {
                if let imageURL = music.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            defaultMusicArtwork
                        @unknown default:
                            defaultMusicArtwork
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    defaultMusicArtwork
                        .frame(width: 50, height: 50)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(music.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(music.artist)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
    }
    
    private var defaultMusicArtwork: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "#1ED760").opacity(0.3),
                        Color(hex: "#1DB954").opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            )
    }
    
    @ViewBuilder
    private var errorMessageView: some View {
        if let error = errorMessage {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal)
        }
    }
    
    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
        !selectedImages.isEmpty || 
        selectedVideo != nil || 
        audioRecordingURL != nil ||
        spotifyLink != nil ||
        poll != nil ||
        leaderboardEntry != nil
    }
    
    
    private func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("\(UUID().uuidString).m4a")
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 12000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            
            isRecording = true
            recordingTime = 0
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingTime += 0.1
                
                // Stop recording automatically at 1 minute (60 seconds)
                if recordingTime >= 60.0 {
                    stopRecording()
                }
            }
            
            audioRecordingURL = audioFilename
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func validateVideoDuration(_ videoURL: URL) async {
        do {
            let asset = AVAsset(url: videoURL)
            let duration = try await asset.load(.duration)
            let durationInSeconds = CMTimeGetSeconds(duration)
            
            if durationInSeconds > 60.0 {
                await MainActor.run {
                    errorMessage = "Video must be 1 minute or less. Your video is \(Int(durationInSeconds)) seconds."
                    selectedVideo = nil
                }
            } else {
                await MainActor.run {
                    errorMessage = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to validate video: \(error.localizedDescription)"
                selectedVideo = nil
            }
        }
    }
    
    private func loadImagesFromPicker(_ items: [PhotosPickerItem]) async {
        // Clear previous images when new selection is made
        await MainActor.run {
            selectedImages.removeAll()
        }
        
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        if selectedImages.count < 4 {
                            selectedImages.append(image)
                        }
                    }
                }
            } catch {
                print("Failed to load image: \(error.localizedDescription)")
            }
        }
    }
    
    private func post() async {
        guard canPost else { return }
        
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }
        
        do {
            // Upload media if selected
            var imageURLs: [URL] = []
            var videoURL: URL? = nil
            var audioURL: URL? = nil
            
            // Upload all selected images (up to 5)
            if !selectedImages.isEmpty {
                isUploadingMedia = true
                for image in selectedImages {
                    if let url = try? await imageService.uploadPostImage(image) {
                        imageURLs.append(url)
                    }
                }
                isUploadingMedia = false
            }
            
            if let video = selectedVideo {
                isUploadingMedia = true
                videoURL = try await mediaService.uploadPostVideo(video)
                isUploadingMedia = false
            }
            
            if let audio = audioRecordingURL {
                isUploadingMedia = true
                audioURL = try await mediaService.uploadPostAudio(audio)
                isUploadingMedia = false
            }
            
            let postText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Debug: Check backgroundMusic state right before posting
            print("🎵 PostComposerView.post(): backgroundMusic state = \(backgroundMusic != nil ? "exists" : "nil")")
            if let bgMusic = backgroundMusic {
                print("🎵 PostComposerView.post(): backgroundMusic details: name=\(bgMusic.name), artist=\(bgMusic.artist), spotifyId=\(bgMusic.spotifyId)")
            }
            
            if let parentPost = parentPost {
                _ = try await service.reply(
                    to: parentPost,
                    text: postText,
                    imageURLs: imageURLs,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    spotifyLink: spotifyLink,
                    poll: poll,
                    backgroundMusic: backgroundMusic
                )
            } else {
                print("📝 Creating post with spotifyLink: \(spotifyLink?.name ?? "nil")")
                print("📝 spotifyLink details: id=\(spotifyLink?.id ?? "nil"), url=\(spotifyLink?.url ?? "nil"), type=\(spotifyLink?.type ?? "nil")")
                print("🎵 Creating post with backgroundMusic: \(backgroundMusic?.name ?? "nil")")
                print("🎵 backgroundMusic details: spotifyId=\(backgroundMusic?.spotifyId ?? "nil"), name=\(backgroundMusic?.name ?? "nil"), artist=\(backgroundMusic?.artist ?? "nil"), previewURL=\(backgroundMusic?.previewURL?.absoluteString ?? "nil")")
                _ = try await service.createPost(
                    text: postText,
                    imageURLs: imageURLs,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    leaderboardEntry: leaderboardEntry,
                    spotifyLink: spotifyLink,
                    poll: poll,
                    backgroundMusic: backgroundMusic
                )
            }
            // Reset form state
            text = ""
            selectedImages = []
            selectedVideo = nil
            audioRecordingURL = nil
            spotifyLink = nil
            poll = nil
            backgroundMusic = nil
            // Note: leaderboardEntry is a let constant, so it can't be reset
            
            onPostCreated?()
            
            // Post notification to refresh feed
            NotificationCenter.default.post(name: .feedDidUpdate, object: nil)
            
            dismiss()
        } catch {
            isUploadingMedia = false
            errorMessage = "Failed to post: \(error.localizedDescription)"
        }
    }
}
