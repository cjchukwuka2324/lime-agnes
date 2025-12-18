import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import Photos

struct PostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    
    let service: FeedService
    let leaderboardEntry: LeaderboardEntrySummary?
    let parentPost: Post?
    let prefilledText: String?
    let onPostCreated: ((String?) -> Void)? // Pass created post ID
    
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
    
    // Mention autocomplete
    @State private var showMentionAutocomplete = false
    @State private var mentionSuggestions: [UserSummary] = []
    @State private var mentionQuery: String = ""
    @State private var mentionSearchTask: Task<Void, Never>?
    @State private var currentMentionRange: NSRange?
    
    // Hashtag autocomplete
    @State private var showHashtagAutocomplete = false
    @State private var hashtagSuggestions: [TrendingHashtag] = []
    @State private var hashtagQuery: String = ""
    @State private var hashtagSearchTask: Task<Void, Never>?
    @State private var currentHashtagRange: NSRange?
    
    private let imageService = FeedImageService.shared
    private let mediaService = FeedMediaService.shared
    private let mentionService: MentionService = SupabaseMentionService.shared
    private let hashtagService: HashtagService = SupabaseHashtagService.shared
    
    init(
        service: FeedService = SupabaseFeedService.shared as FeedService,
        leaderboardEntry: LeaderboardEntrySummary? = nil,
        parentPost: Post? = nil,
        prefilledText: String? = nil,
        onPostCreated: ((String?) -> Void)? = nil
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
            .navigationTitle(parentPost == nil ? GreenRoomBranding.composerTitleNew : GreenRoomBranding.composerTitleReply)
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
                            Text(parentPost == nil ? GreenRoomBranding.composerButtonNew : GreenRoomBranding.composerButtonReply)
                                .fontWeight(.semibold)
                                .foregroundColor(canPost ? .white : .gray)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(canPost ? Color(hex: "#1ED760") : Color.gray.opacity(0.3))
                                )
                        }
                    }
                    .disabled(!canPost || isPosting || isUploadingMedia || isRecording)
                }
            }
            .photosPicker(
                isPresented: $showImagePicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 4,
                matching: .any(of: [.images, .videos])
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
        // Solid black background with green highlights
        Color(hex: "#000000")
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
    
    @State private var videoThumbnail: UIImage?
    
    private func videoPreview(videoURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Video")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button {
                    self.selectedVideo = nil
                    self.videoThumbnail = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            ZStack(alignment: .center) {
                if let thumbnail = videoThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                }
                
                // Play button overlay
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white.opacity(0.9))
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.3))
                    )
            }
        }
        .onAppear {
            generateVideoThumbnail(from: videoURL)
        }
        .onChange(of: selectedVideo) { _, newVideoURL in
            if let newVideoURL = newVideoURL {
                generateVideoThumbnail(from: newVideoURL)
            } else {
                videoThumbnail = nil
            }
        }
    }
    
    private func generateVideoThumbnail(from videoURL: URL) {
        Task {
            let asset = AVAsset(url: videoURL)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            
            do {
                let cgImage = try await imageGenerator.image(at: CMTime.zero).image
                let thumbnail = UIImage(cgImage: cgImage)
                await MainActor.run {
                    self.videoThumbnail = thumbnail
                }
            } catch {
                print("Failed to generate video thumbnail: \(error.localizedDescription)")
            }
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
            Text(parentPost == nil ? GreenRoomBranding.composerPlaceholderNew : GreenRoomBranding.composerPlaceholderReply)
                .font(.headline)
                .foregroundColor(.white)
            
            ZStack(alignment: .topLeading) {
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
                    .onChange(of: text) { oldValue, newValue in
                        detectMention(in: newValue)
                        detectHashtag(in: newValue)
                    }
                
                // Mention autocomplete overlay
                if showMentionAutocomplete && !mentionSuggestions.isEmpty {
                    VStack {
                        Spacer()
                        MentionAutocompleteView(
                            suggestions: mentionSuggestions,
                            onSelect: { user in
                                insertMention(user: user)
                            }
                        )
                        .padding(.top, 8)
                    }
                }
                
                // Hashtag autocomplete overlay
                if showHashtagAutocomplete && !hashtagSuggestions.isEmpty {
                    VStack {
                        Spacer()
                        HashtagAutocompleteView(
                            suggestions: hashtagSuggestions,
                            onSelect: { hashtag in
                                insertHashtag(hashtag: hashtag)
                            }
                        )
                        .padding(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                    }
                }
            }
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
            .foregroundColor(Color(hex: "#1ED760"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#1ED760").opacity(0.15))
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
            .foregroundColor(isRecording ? Color.red : Color(hex: "#1ED760"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isRecording ? Color.red.opacity(0.2) : Color(hex: "#1ED760").opacity(0.15))
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
            .foregroundColor(Color(hex: "#1ED760"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#1ED760").opacity(0.15))
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
            .foregroundColor(Color(hex: "#1ED760"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#1ED760").opacity(0.15))
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
            .foregroundColor(Color(hex: "#1ED760"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "#1ED760").opacity(0.15))
            )
        }
        .disabled(isPosting || isUploadingMedia || isRecording)
    }
    
    // MARK: - Preview Sections
    
    private func spotifyLinkPreview(link: SpotifyLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Music Link")
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
        // Clear previous media when new selection is made
        await MainActor.run {
            selectedImages.removeAll()
            selectedVideo = nil
        }
        
        for item in items {
            do {
                // Check supported content types to determine if it's a video
                let supportedTypes = item.supportedContentTypes
                let isVideo = supportedTypes.contains { type in
                    type.conforms(to: .movie) || type.identifier == "public.movie" || type.identifier.contains("video")
                }
                
                if isVideo {
                    // It's a video - try to load as file representation
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        // Save video data to temporary file
                        let tempDir = FileManager.default.temporaryDirectory
                        let videoURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
                        
                        do {
                            try data.write(to: videoURL)
                            await MainActor.run {
                                // Only allow one video, and clear images if video is selected
                                selectedImages.removeAll()
                                selectedVideo = videoURL
                                // Validate video duration
                                Task {
                                    await validateVideoDuration(videoURL)
                                }
                            }
                        } catch {
                            print("Failed to save video: \(error.localizedDescription)")
                        }
                    } else {
                        // Fallback: try using PHAsset if available
                        if let identifier = item.itemIdentifier {
                            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                            if let asset = fetchResult.firstObject, asset.mediaType == .video {
                                let options = PHVideoRequestOptions()
                                options.version = .current
                                options.deliveryMode = .highQualityFormat
                                options.isNetworkAccessAllowed = true
                                
                                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                                    PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, errorInfo in
                                        if let errorInfo = errorInfo {
                                            print("Error loading video: \(errorInfo)")
                                            continuation.resume()
                                            return
                                        }
                                        
                                        if let urlAsset = avAsset as? AVURLAsset {
                                            let sourceURL = urlAsset.url
                                            // Copy to temporary location
                                            let tempDir = FileManager.default.temporaryDirectory
                                            let videoURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
                                            
                                            do {
                                                if FileManager.default.fileExists(atPath: videoURL.path) {
                                                    try FileManager.default.removeItem(at: videoURL)
                                                }
                                                try FileManager.default.copyItem(at: sourceURL, to: videoURL)
                                                
                                                Task { @MainActor in
                                                    // Only allow one video, and clear images if video is selected
                                                    selectedImages.removeAll()
                                                    selectedVideo = videoURL
                                                    // Validate video duration
                                                    Task {
                                                        await validateVideoDuration(videoURL)
                                                    }
                                                }
                                            } catch {
                                                print("Failed to copy video: \(error.localizedDescription)")
                                            }
                                        }
                                        continuation.resume()
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Try to load as image
                    if let data = try await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            // Only add images if no video is selected
                            if selectedVideo == nil && selectedImages.count < 4 {
                                selectedImages.append(image)
                            }
                        }
                    }
                }
            } catch {
                print("Failed to load media: \(error.localizedDescription)")
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
                print("📹 Starting video upload for: \(video.lastPathComponent)")
                print("📹 Video file exists: \(FileManager.default.fileExists(atPath: video.path))")
                
                // Ensure file exists and is accessible
                guard FileManager.default.fileExists(atPath: video.path) else {
                    isUploadingMedia = false
                    let errorMsg = "Video file not found at path: \(video.path)"
                    print("❌ \(errorMsg)")
                    errorMessage = errorMsg
                    throw NSError(domain: "PostComposerView", code: 404, userInfo: [NSLocalizedDescriptionKey: errorMsg])
                }
                
                // Check file size and show compression message if needed
                if let attributes = try? FileManager.default.attributesOfItem(atPath: video.path),
                   let fileSize = attributes[.size] as? Int64,
                   fileSize > 10 * 1024 * 1024 { // 10MB
                    print("📹 Video is large (\(fileSize / 1024 / 1024)MB), will compress before upload")
                }
                
                do {
                    videoURL = try await mediaService.uploadPostVideo(video)
                    print("✅ Video uploaded successfully: \(videoURL?.absoluteString ?? "nil")")
                    isUploadingMedia = false
                } catch {
                    isUploadingMedia = false
                    print("❌ Video upload failed: \(error.localizedDescription)")
                    if let nsError = error as NSError? {
                        print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                        print("❌ Error userInfo: \(nsError.userInfo)")
                    }
                    
                    // Provide user-friendly error message
                    if let storageError = error as NSError?, storageError.domain.contains("Storage") {
                        errorMessage = "Video is too large. Please try a shorter video or lower quality."
                    } else {
                        errorMessage = "Failed to upload video: \(error.localizedDescription)"
                    }
                    throw error
                }
            }
            
            if let audio = audioRecordingURL {
                isUploadingMedia = true
                audioURL = try await mediaService.uploadPostAudio(audio)
                isUploadingMedia = false
            }
            
            let postText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Extract mentioned user IDs from text
            let mentionedUserIds = extractMentionedUserIds(from: postText)
            
            // Debug: Check backgroundMusic state right before posting
            print("🎵 PostComposerView.post(): backgroundMusic state = \(backgroundMusic != nil ? "exists" : "nil")")
            if let bgMusic = backgroundMusic {
                print("🎵 PostComposerView.post(): backgroundMusic details: name=\(bgMusic.name), artist=\(bgMusic.artist), spotifyId=\(bgMusic.spotifyId)")
            }
            
            print("📤 Posting with:")
            print("📤 Text: \(postText.isEmpty ? "empty" : postText)")
            print("📤 Images: \(imageURLs.count)")
            print("📤 Video: \(videoURL?.absoluteString ?? "nil")")
            print("📤 Audio: \(audioURL?.absoluteString ?? "nil")")
            print("📤 Mentions: \(mentionedUserIds.count) users")
            
            let createdPostId: String?
            if let parentPost = parentPost {
                print("📤 Creating reply to post: \(parentPost.id)")
                let reply = try await service.reply(
                    to: parentPost,
                    text: postText,
                    imageURLs: imageURLs,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    spotifyLink: spotifyLink,
                    poll: poll,
                    backgroundMusic: backgroundMusic,
                    mentionedUserIds: mentionedUserIds
                )
                createdPostId = reply.id
                print("✅ Reply created successfully with ID: \(reply.id)")
            } else {
                print("📝 Creating new post")
                print("📝 spotifyLink: \(spotifyLink?.name ?? "nil")")
                print("🎵 backgroundMusic: \(backgroundMusic?.name ?? "nil")")
                let post = try await service.createPost(
                    text: postText,
                    imageURLs: imageURLs,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    leaderboardEntry: leaderboardEntry,
                    spotifyLink: spotifyLink,
                    poll: poll,
                    backgroundMusic: backgroundMusic,
                    mentionedUserIds: mentionedUserIds
                )
                createdPostId = post.id
                print("✅ Post created successfully with ID: \(post.id)")
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
            
            onPostCreated?(createdPostId)
            
            // Post notification to refresh feed
            NotificationCenter.default.post(name: .feedDidUpdate, object: nil)
            
            dismiss()
        } catch {
            isUploadingMedia = false
            let errorDescription = error.localizedDescription
            print("❌ Post failed with error: \(errorDescription)")
            print("❌ Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ Error userInfo: \(nsError.userInfo)")
            }
            errorMessage = "Failed to post: \(errorDescription)"
        }
    }
    
    // MARK: - Mention Detection
    
    private func detectMention(in text: String) {
        // Find the last @ symbol and extract the query
        guard let lastAtIndex = text.lastIndex(of: "@") else {
            showMentionAutocomplete = false
            mentionSuggestions = []
            return
        }
        
        // Check if there's a space after @ (mention is complete)
        let afterAt = text.index(after: lastAtIndex)
        if afterAt < text.endIndex {
            let remainingText = String(text[afterAt...])
            if remainingText.contains(where: { $0.isWhitespace || $0.isNewline }) {
                // Mention is complete, hide autocomplete
                showMentionAutocomplete = false
                mentionSuggestions = []
                return
            }
        }
        
        // Extract query after @
        let queryStart = text.index(after: lastAtIndex)
        let query = String(text[queryStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        if query.isEmpty {
            showMentionAutocomplete = false
            mentionSuggestions = []
            return
        }
        
        // Store the range for later replacement
        let nsRange = NSRange(location: text.distance(from: text.startIndex, to: lastAtIndex), length: text.distance(from: lastAtIndex, to: text.endIndex))
        currentMentionRange = nsRange
        mentionQuery = query
        
        // Cancel previous search
        mentionSearchTask?.cancel()
        
        // Debounce search
        mentionSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            
            if !Task.isCancelled {
                do {
                    let results = try await mentionService.searchUsers(query: query)
                    await MainActor.run {
                        if !Task.isCancelled {
                            mentionSuggestions = results
                            showMentionAutocomplete = true
                        }
                    }
                } catch {
                    print("Failed to search users for mention: \(error)")
                }
            }
        }
    }
    
    private func insertMention(user: UserSummary) {
        guard let range = currentMentionRange else { return }
        
        let nsText = text as NSString
        // Strip "@" from handle if it already includes it
        let handle = user.handle.hasPrefix("@") ? String(user.handle.dropFirst()) : user.handle
        let mentionText = "@\(handle) "
        let newText = nsText.replacingCharacters(in: range, with: mentionText)
        
        text = newText
        showMentionAutocomplete = false
        mentionSuggestions = []
        currentMentionRange = nil
        mentionQuery = ""
    }
    
    private func extractMentionedUserIds(from text: String) -> [String] {
        // Extract @mentions using regex
        let pattern = #"@(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: text, options: [], range: range)
        
        var mentionedHandles: Set<String> = []
        for match in matches {
            if match.numberOfRanges > 1 {
                let handleRange = match.range(at: 1)
                let handle = nsString.substring(with: handleRange)
                mentionedHandles.insert(handle)
            }
        }
        
        // Convert handles to user IDs by looking them up in mentionSuggestions
        // Note: This is a simplified version that only matches users from autocomplete
        // In production, you might want to do a server-side lookup for all handles
        var userIds: [String] = []
        for handle in mentionedHandles {
            if let user = mentionSuggestions.first(where: { $0.handle == handle }) {
                userIds.append(user.id)
            }
        }
        
        return userIds
    }
    
    // MARK: - Hashtag Detection
    
    private func detectHashtag(in text: String) {
        // Find the last # symbol and extract the query
        guard let lastHashIndex = text.lastIndex(of: "#") else {
            showHashtagAutocomplete = false
            hashtagSuggestions = []
            return
        }
        
        // Check if there's a space after # (hashtag is complete)
        let afterHash = text.index(after: lastHashIndex)
        if afterHash < text.endIndex {
            let remainingText = String(text[afterHash...])
            if remainingText.contains(where: { $0.isWhitespace || $0.isNewline }) {
                // Hashtag is complete, hide autocomplete
                showHashtagAutocomplete = false
                hashtagSuggestions = []
                return
            }
        }
        
        // Extract query after #
        let queryStart = text.index(after: lastHashIndex)
        // Get text from # to end, but stop at whitespace or newline
        let remainingText = String(text[queryStart...])
        let queryEnd = remainingText.firstIndex(where: { $0.isWhitespace || $0.isNewline }) ?? remainingText.endIndex
        let query = String(remainingText[..<queryEnd])
        
        // Store the range for later replacement (include the # and query)
        let rangeLength = text.distance(from: lastHashIndex, to: queryStart) + query.count
        let nsRange = NSRange(location: text.distance(from: text.startIndex, to: lastHashIndex), length: rangeLength)
        currentHashtagRange = nsRange
        hashtagQuery = query
        
        // Cancel previous search
        hashtagSearchTask?.cancel()
        
        // Debounce search (shorter delay for hashtags)
        hashtagSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            
            if !Task.isCancelled {
                do {
                    // Show trending hashtags even if query is empty (just typed #)
                    // Pass empty string to get trending hashtags
                    let searchQuery = query.isEmpty ? "" : query
                    let results = try await hashtagService.searchHashtags(query: searchQuery, limit: 10)
                    await MainActor.run {
                        if !Task.isCancelled {
                            hashtagSuggestions = results
                            showHashtagAutocomplete = !results.isEmpty
                        }
                    }
                } catch {
                    print("Failed to search hashtags: \(error)")
                    await MainActor.run {
                        hashtagSuggestions = []
                        showHashtagAutocomplete = false
                    }
                }
            }
        }
    }
    
    private func insertHashtag(hashtag: TrendingHashtag) {
        guard let range = currentHashtagRange else { return }
        
        let nsText = text as NSString
        let hashtagText = "#\(hashtag.tag) "
        let newText = nsText.replacingCharacters(in: range, with: hashtagText)
        
        text = newText
        showHashtagAutocomplete = false
        hashtagSuggestions = []
        currentHashtagRange = nil
        hashtagQuery = ""
    }
}
