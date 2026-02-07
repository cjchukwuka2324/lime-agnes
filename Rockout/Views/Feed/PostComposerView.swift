import SwiftUI
import AVFoundation
import AVKit
import PhotosUI
import Photos
import UIKit
import UniformTypeIdentifiers

struct PostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sizeCategory) private var sizeCategory
    
    @State private var currentUser: UserSummary?
    
    let service: FeedService
    let leaderboardEntry: LeaderboardEntrySummary?
    let parentPost: Post?
    let resharedPostId: String?
    let prefilledText: String?
    let onPostCreated: ((String?) -> Void)? // Pass created post ID
    
    @State private var text: String
    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var selectedImages: [UIImage] = [] // Up to 5 images
    @State private var selectedVideo: URL?
    @State private var videoThumbnail: UIImage?
    @State private var audioRecordingURL: URL?
    @State private var isAudioPreviewPlaying: Bool = false
    @State private var audioPreviewPlayer: AVAudioPlayer?
    @State private var audioPreviewTime: TimeInterval = 0
    @State private var audioPreviewTimer: Timer?
    @State private var isAudioPreviewScrubbing: Bool = false
    @State private var recordingTime: TimeInterval = 0
    @State private var isUploadingMedia = false
    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    @State private var showImageCrop = false
    @State private var imageToCrop: UIImage?
    @State private var showVideoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoLibraryImages = false
    @State private var showPhotoLibraryVideo = false
    @State private var selectedVideoPickerItem: PhotosPickerItem? = nil
    @State private var spotifyLink: SpotifyLink?
    @State private var poll: Poll?
    @State private var showSpotifyLinkAdd = false
    @State private var showPollCreation = false
    @State private var showVoiceRecordingView = false
    @FocusState private var isTextEditorFocused: Bool
    @State private var textEditorHeight: CGFloat = 28

    @State private var showImageViewer = false
    @State private var imageViewerStartIndex = 0
    @State private var showVideoPlayer = false
    
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
        resharedPostId: String? = nil,
        prefilledText: String? = nil,
        onPostCreated: ((String?) -> Void)? = nil
    ) {
        self.service = service
        self.leaderboardEntry = leaderboardEntry
        self.parentPost = parentPost
        self.resharedPostId = resharedPostId
        self.prefilledText = prefilledText
        self.onPostCreated = onPostCreated
        self._text = State(initialValue: prefilledText ?? "")
    }
    
    var body: some View {
        mainContent
    }
    
    private var mainContent: some View {
        NavigationStack {
            mainContentView
                .toolbar {
                    toolbarContent
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .onAppear {
                    // Configure UINavigationBar appearance to remove default styling
                    let appearance = UINavigationBarAppearance()
                    appearance.configureWithTransparentBackground()
                    appearance.backgroundColor = .clear
                    appearance.shadowColor = .clear
                    UINavigationBar.appearance().standardAppearance = appearance
                    UINavigationBar.appearance().scrollEdgeAppearance = appearance
                    UINavigationBar.appearance().compactAppearance = appearance
                }
                .onDisappear {
                    stopAudioPreview()
                }
        }
    }
    
    
    private var mainContentView: some View {
        baseContentView
            .fullScreenCover(isPresented: $showPhotoLibraryImages) {
                FullScreenPHPickerView(
                    isPresented: $showPhotoLibraryImages,
                    selectionLimit: 4,
                    filter: .images
                ) { results in
                    handleImagePickerResults(results)
                }
            }
            .fullScreenCover(isPresented: $showPhotoLibraryVideo) {
                FullScreenPHPickerView(
                    isPresented: $showPhotoLibraryVideo,
                    selectionLimit: 1,
                    filter: .videos
                ) { results in
                    handleVideoPickerResults(results)
                }
            }
            .sheet(isPresented: $showImageCrop) {
                imageCropSheet
            }
            .sheet(isPresented: $showVideoPicker) {
                VideoPicker(selectedVideoURL: $selectedVideo)
            }
            .fullScreenCover(isPresented: $showCameraPicker) {
                CameraPickerView(
                    selectedImages: $selectedImages,
                    selectedVideo: $selectedVideo
                )
                .ignoresSafeArea()
                .background(Color.black.ignoresSafeArea())
            }
            .sheet(isPresented: $showSpotifyLinkAdd) {
                SpotifyLinkAddView(selectedSpotifyLink: $spotifyLink)
            }
            .sheet(isPresented: $showPollCreation) {
                PollCreationView(poll: $poll)
            }
            .sheet(isPresented: $showVoiceRecordingView) {
                voiceRecordingSheet
            }
            .fullScreenCover(isPresented: $showImageViewer) {
                ImageFullScreenViewer(images: selectedImages, startIndex: imageViewerStartIndex)
            }
            .fullScreenCover(isPresented: $showVideoPlayer) {
                if let url = selectedVideo {
                    VideoFullScreenPlayer(url: url)
                }
            }
            .onChange(of: selectedVideo) { _, newVideoURL in
                if let videoURL = newVideoURL {
                    Task {
                        await validateVideoDuration(videoURL)
                    }
                    generateVideoThumbnail(from: videoURL)
                } else {
                    videoThumbnail = nil
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task {
                    await loadImagesFromPicker(newItems)
                }
            }
            .onChange(of: selectedVideoPickerItem) { _, newItem in
                Task {
                    await loadVideoFromPicker(newItem)
                }
            }
            .onChange(of: audioRecordingURL) { _, newURL in
                stopAudioPreview()
                audioPreviewTime = 0
            }
    }
    
    private var baseContentView: some View {
        ZStack(alignment: .bottom) {
            backgroundGradient
            ScrollView {
                contentView
            }
            
            // Keyboard accessory bar positioned above keyboard
            keyboardAccessoryBar
                .padding(.horizontal, 20)
                .padding(.bottom, 0)
                .background(Color.black)
        }
        .onAppear {
            handleOnAppear()
        }
    }
    
    @ViewBuilder
    private var imageCropSheet: some View {
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
    
    private var voiceRecordingSheet: some View {
        VoiceRecordingView { recordingURL in
            if let url = recordingURL {
                self.audioRecordingURL = url
                // Get duration from the audio file
                Task {
                    await self.updateRecordingDuration(from: url)
                }
            } else {
                self.audioRecordingURL = nil
                self.recordingTime = 0
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") {
                dismiss()
            }
            .foregroundColor(.white)
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            dropButton
        }
    }
    
    private var dropButton: some View {
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
                    .foregroundColor(canPost ? Color(hex: "#1ED760") : .gray)
            }
        }
        .disabled(!canPost || isPosting || isUploadingMedia)
    }
    
    private func handleOnAppear() {
        #if DEBUG
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        #else
        let isPreview = false
        #endif

        guard !isPreview else { return }

        Task {
            currentUser = await SupabaseSocialGraphService.shared.currentUser()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextEditorFocused = true
        }
    }
    
    private func dismissKeyboardGlobally() {
        isTextEditorFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var backgroundGradient: some View {
        // Solid black background with green highlights
        Color(hex: "#000000")
            .ignoresSafeArea()
    }
    
    private var contentView: some View {
        AnyView(
            VStack(spacing: 16) {
                if let entry = leaderboardEntry {
                    leaderboardPreview(entry: entry)
                }
                
                // Removed image, video, and audio previews here as per instructions
                
                // Removed spotifyLink preview as per instructions
                
                // Removed poll preview as per instructions
                
                // Removed backgroundMusic preview as per instructions
                
                textEditorView
                
                // Removed audio preview here as well
                
                errorMessageView
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        )
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
                        selectedPhotoItems = []
                        showPhotoLibraryImages = true
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
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    imageViewerStartIndex = index
                                    showImageViewer = true
                                }
                            
                            Button {
                                selectedImages.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            .padding(2)
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
    
    private var textEditorView: some View {
        AnyView(
            HStack(alignment: .top, spacing: 12) {
                // Profile picture
                Group {
                    if let user = currentUser {
                        if let imageURL = user.profilePictureURL {
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
                                    defaultAvatar(initials: user.avatarInitials)
                                @unknown default:
                                    defaultAvatar(initials: user.avatarInitials)
                                }
                            }
                        } else {
                            defaultAvatar(initials: user.avatarInitials)
                        }
                    } else {
                        defaultAvatar(initials: "U")
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                // Right column: TextEditor (with in-editor prompt) above chips
                VStack(alignment: .leading, spacing: 8) {
                    // Editor area with overlays
                    ZStack(alignment: .topLeading) {
                        GeometryReader { geo in
                            TextEditor(text: $text)
                                .font(.body)
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .scrollDisabled(textEditorHeight < editorMaxHeight)
                                .focused($isTextEditorFocused)
                                .onChange(of: text) { oldValue, newValue in
                                    detectMention(in: newValue)
                                    detectHashtag(in: newValue)
                                    textEditorHeight = measuredTextEditorHeight(for: newValue, width: geo.size.width)
                                }
                                .onAppear {
                                    textEditorHeight = measuredTextEditorHeight(for: text, width: geo.size.width)
                                }
                        }
                        
                        // Placeholder INSIDE the editor, visible even when attachments exist
                        if text.isEmpty {
                            Text(parentPost == nil ? GreenRoomBranding.composerPlaceholderNew : GreenRoomBranding.composerPlaceholderReply)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.top, placeholderTopPadding)
                                .padding(.leading, placeholderLeadingPadding)
                                .allowsHitTesting(false)
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
                    .frame(height: textEditorHeight)
                    .clipped()
                    
                    // Chips directly below the editor (Twitter-style)
                    Group {
                        if audioRecordingURL != nil {
                            audioAttachmentChip
                        }
                        if !selectedImages.isEmpty {
                            imagesAttachmentChip
                        }
                        if selectedVideo != nil {
                            videoAttachmentChip
                        }
                        if spotifyLink != nil {
                            spotifyLinkAttachmentChip
                        }
                        if poll != nil {
                            pollAttachmentChip
                        }
                    }
                }
            }
        )
    }
    
    private var editorMaxHeight: CGFloat {
        160 // Maximum expanded height before the editor starts scrolling
    }
    
    private var placeholderTopPadding: CGFloat {
        let base: CGFloat = 8
        let metrics = UIFontMetrics(forTextStyle: .body)
        return metrics.scaledValue(for: base)
    }
    
    private var placeholderLeadingPadding: CGFloat {
        let base: CGFloat = 5
        let metrics = UIFontMetrics(forTextStyle: .body)
        return metrics.scaledValue(for: base)
    }
    
    private func measuredTextEditorHeight(for text: String, width: CGFloat) -> CGFloat {
        // Approximate internal padding of TextEditor’s text container
        let horizontalPadding: CGFloat = 10
        let verticalPadding: CGFloat = 12

        let font = UIFont.preferredFont(forTextStyle: .body)
        let metrics = UIFontMetrics(forTextStyle: .body)
        let lineHeight = metrics.scaledValue(for: font.lineHeight)

        let minHeight = max(28, lineHeight + verticalPadding)
        let maxHeight = editorMaxHeight

        // Use a single space for empty text to get a stable single-line measurement
        let measuringText = text.isEmpty ? " " : text

        let constraintSize = CGSize(width: max(0, width - horizontalPadding), height: .greatestFiniteMagnitude)
        let bounding = (measuringText as NSString).boundingRect(
            with: constraintSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )

        let calculated = ceil(bounding.height) + verticalPadding
        return min(max(minHeight, calculated), maxHeight)
    }
    
    private var audioAttachmentChip: some View {
        HStack(alignment: .center, spacing: 8) {
            // Play/Pause
            Button {
                if isAudioPreviewPlaying {
                    pauseAudioPreview()
                } else {
                    startAudioPreview()
                }
            } label: {
                Image(systemName: isAudioPreviewPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(.black)
                    .padding(6)
                    .background(Circle().fill(Color(hex: "#1ED760")))
            }
            
            // Scrubber + time labels
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { audioPreviewTime },
                    set: { newValue in
                        audioPreviewTime = newValue
                    }
                ), in: 0...(recordingTime > 0 ? recordingTime : 1), onEditingChanged: { editing in
                    isAudioPreviewScrubbing = editing
                    if !editing {
                        seekAudioPreview(to: audioPreviewTime)
                    }
                })
                .disabled(recordingTime <= 0)
                .tint(Color(hex: "#1ED760"))
                
                HStack {
                    Text(formatTime(audioPreviewTime))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer(minLength: 0)
                    Text(formatTime(recordingTime))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Remove attachment
            Button {
                stopAudioPreview()
                audioRecordingURL = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black)
        )
    }
    
    private var imagesAttachmentChip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                imageViewerStartIndex = index
                                showImageViewer = true
                            }
                        Button {
                            selectedImages.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .padding(2)
                    }
                }
            }
            .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black)
        )
        .frame(height: 72)
    }
    
    private var videoAttachmentChip: some View {
        HStack(spacing: 8) {
            ZStack {
                if let thumb = videoThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "film")
                                .foregroundColor(.white.opacity(0.8))
                        )
                }
                Image(systemName: "play.fill")
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showVideoPlayer = true
            }
            
            Text("Video attached")
                .font(.caption)
                .foregroundColor(.white)
            
            Spacer(minLength: 0)
            
            Button {
                selectedVideo = nil
                videoThumbnail = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black)
        )
    }
    
    private var spotifyLinkAttachmentChip: some View {
        HStack(spacing: 8) {
            if let link = spotifyLink {
                HStack(spacing: 12) {
                    // Cover Art with inner padding so it doesn't touch borders
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                        if let imageURL = link.imageURL {
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .tint(.white)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .padding(2)
                                case .failure:
                                    defaultMusicArtwork
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .padding(2)
                                @unknown default:
                                    defaultMusicArtwork
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .padding(2)
                                }
                            }
                        } else {
                            defaultMusicArtwork
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .padding(2)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Track title and artist/owner
                    VStack(alignment: .leading, spacing: 4) {
                        Text(link.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if link.type == "track", let artist = link.artist {
                            Text(artist)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else if link.type == "playlist", let owner = link.owner {
                            Text("Playlist • \(owner)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .frame(height: 56)
                .layoutPriority(1)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .foregroundColor(.black)
                        .padding(6)
                        .background(Circle().fill(Color(hex: "#1ED760")))
                    Text("Music link")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .layoutPriority(1)
            }

            Spacer(minLength: 0)

            Button {
                spotifyLink = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black)
        )
    }

    private var pollAttachmentChip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar")
                    .foregroundColor(.black)
                    .padding(6)
                    .background(Circle().fill(Color(hex: "#1ED760")))
                Text(poll?.question ?? "Poll")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    poll = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            if let poll = poll {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(poll.options.prefix(3).enumerated()), id: \.element.id) { index, option in
                        HStack(spacing: 6) {
                            Image(systemName: poll.type == "single" ? "circle" : "square")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.caption2)
                            Text(option.text)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                    }
                    if poll.options.count > 3 {
                        Text("+\(poll.options.count - 3) more options")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black)
        )
    }
    
    private func defaultAvatar(initials: String) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "#1ED760").opacity(0.6),
                        Color(hex: "#1DB954").opacity(0.4)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
    
    private var mediaButtonsRow: some View {
        HStack(spacing: 12) {
            cameraButton
            voiceButton
            musicButton
            pollButton
        }
        .padding(.vertical, 8)
    }

    // Compact keyboard accessory bar (Twitter-style)
    private var keyboardAccessoryBar: some View {
        HStack(spacing: 8) {
            compactTakePhotoVideoButton
                .frame(maxWidth: .infinity)
            compactChoosePhotosButton
                .frame(maxWidth: .infinity)
            compactChooseVideoButton
                .frame(maxWidth: .infinity)
            compactVoiceButton
                .frame(maxWidth: .infinity)
            compactMusicButton
                .frame(maxWidth: .infinity)
            compactPollButton
                .frame(maxWidth: .infinity)
        }
        .frame(height: 44)
        .padding(.horizontal, 0)
        .padding(.vertical, 4)
        .background(Color.black)
    }

    private var compactCameraButton: some View {
        Menu {
            Button {
                dismissKeyboardGlobally()
                showCameraPicker = true
            } label: {
                Label("Take Photo/Video", systemImage: "camera")
            }
            Button {
                selectedPhotoItems = []
                showPhotoLibraryImages = true
            } label: {
                Label("Choose Photos", systemImage: "photo")
            }
            Button {
                selectedVideoPickerItem = nil
                showPhotoLibraryVideo = true
            } label: {
                Label("Choose Video", systemImage: "film")
            }
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "#1ED760"))
                .frame(width: 24, height: 24)
        }
        .disabled(isPosting || isUploadingMedia)
    }

    private var compactVoiceButton: some View {
        Button {
            showVoiceRecordingView = true
        } label: {
            Image(systemName: audioRecordingURL != nil ? "waveform" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "#1ED760"))
                .frame(width: 24, height: 24)
        }
        .disabled(isPosting || isUploadingMedia || !selectedImages.isEmpty || selectedVideo != nil)
    }

    private var compactMusicButton: some View {
        Button {
            showSpotifyLinkAdd = true
        } label: {
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "#1ED760"))
                .frame(width: 24, height: 24)
        }
        .disabled(isPosting || isUploadingMedia)
    }

    private var compactPollButton: some View {
        Button {
            showPollCreation = true
        } label: {
            Image(systemName: "chart.bar")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "#1ED760"))
                .frame(width: 24, height: 24)
        }
        .disabled(isPosting || isUploadingMedia)
    }

    private var compactTakePhotoVideoButton: some View {
        Button {
            dismissKeyboardGlobally()
            showCameraPicker = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "#1ED760"))
                .frame(width: 24, height: 24)
        }
        .disabled(isPosting || isUploadingMedia)
    }

    private var compactChoosePhotosButton: some View {
        Button {
            selectedPhotoItems = []
            showPhotoLibraryImages = true
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "#1ED760"))
                .frame(width: 24, height: 24)
        }
        .disabled(isPosting || isUploadingMedia)
    }

    private var compactChooseVideoButton: some View {
        Button {
            selectedVideoPickerItem = nil
            showPhotoLibraryVideo = true
        } label: {
            Image(systemName: "film")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(hex: "#1ED760"))
                .frame(width: 24, height: 24)
        }
        .disabled(isPosting || isUploadingMedia)
    }
    
    private var cameraButton: some View {
        Menu {
            Button {
                dismissKeyboardGlobally()
                showCameraPicker = true
            } label: {
                Label("Take Photo/Video", systemImage: "camera")
            }
            Button {
                selectedPhotoItems = []
                showPhotoLibraryImages = true
            } label: {
                Label("Choose Photos", systemImage: "photo")
            }
            Button {
                selectedVideoPickerItem = nil
                showPhotoLibraryVideo = true
            } label: {
                Label("Choose Video", systemImage: "film")
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
        .disabled(isPosting || isUploadingMedia)
    }
    
    private var voiceButton: some View {
        Button {
            showVoiceRecordingView = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: audioRecordingURL != nil ? "waveform" : "mic.fill")
                    .font(.title3)
                Text(audioRecordingURL != nil ? formatTime(recordingTime) : "Voice")
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
        .disabled(isPosting || isUploadingMedia)
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
        .disabled(isPosting || isUploadingMedia)
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
    
    
    private func updateRecordingDuration(from url: URL) async {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            await MainActor.run {
                self.recordingTime = player.duration
            }
        } catch {
            print("Failed to get recording duration: \(error)")
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
    
    private func loadVideoFromPicker(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        // Clear previous media when new selection is made
        await MainActor.run {
            selectedImages.removeAll()
            selectedVideo = nil
        }

        do {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let tempDir = FileManager.default.temporaryDirectory
                let videoURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
                do {
                    try data.write(to: videoURL)
                    await MainActor.run {
                        selectedImages.removeAll()
                        selectedVideo = videoURL
                        Task {
                            await validateVideoDuration(videoURL)
                        }
                    }
                } catch {
                    print("Failed to save video: \(error.localizedDescription)")
                }
            } else if let identifier = item.itemIdentifier {
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
                                let tempDir = FileManager.default.temporaryDirectory
                                let videoURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
                                do {
                                    if FileManager.default.fileExists(atPath: videoURL.path) {
                                        try FileManager.default.removeItem(at: videoURL)
                                    }
                                    try FileManager.default.copyItem(at: sourceURL, to: videoURL)
                                    Task { @MainActor in
                                        selectedImages.removeAll()
                                        selectedVideo = videoURL
                                        Task { await validateVideoDuration(videoURL) }
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
        } catch {
            print("Failed to load video: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Custom PHPicker handling
    
    private func handleImagePickerResults(_ results: [PHPickerResult]) {
        // If user cancelled, do nothing
        guard !results.isEmpty else { return }
        Task { @MainActor in
            // Clear previous media when new selection is made
            self.selectedImages.removeAll()
            self.selectedVideo = nil
        }
        for result in results {
            let provider = result.itemProvider
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, error in
                    if let image = object as? UIImage {
                        Task { @MainActor in
                            if self.selectedVideo == nil && self.selectedImages.count < 4 {
                                self.selectedImages.append(image)
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleVideoPickerResults(_ results: [PHPickerResult]) {
        // Expect at most 1 result; if none, user cancelled
        guard let result = results.first else { return }
        let provider = result.itemProvider
        // Attempt to load a movie file
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                guard let sourceURL = url else { return }
                let tempDir = FileManager.default.temporaryDirectory
                let destURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try? FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                    Task { @MainActor in
                        // Only allow one video; clear images if video is selected
                        self.selectedImages.removeAll()
                        self.selectedVideo = destURL
                    }
                    Task {
                        await self.validateVideoDuration(destURL)
                    }
                    self.generateVideoThumbnail(from: destURL)
                } catch {
                    print("Failed to copy video from picker: \(error.localizedDescription)")
                }
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
                stopAudioPreview()
                isUploadingMedia = true
                audioURL = try await mediaService.uploadPostAudio(audio)
                isUploadingMedia = false
            }
            
            let postText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Extract mentioned user IDs from text
            let mentionedUserIds = extractMentionedUserIds(from: postText)
            
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
                    backgroundMusic: nil,
                    mentionedUserIds: mentionedUserIds
                )
                createdPostId = reply.id
                print("✅ Reply created successfully with ID: \(reply.id)")
            } else {
                print("📝 Creating new post")
                print("📝 spotifyLink: \(spotifyLink?.name ?? "nil")")
                let post = try await service.createPost(
                    text: postText,
                    imageURLs: imageURLs,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    leaderboardEntry: leaderboardEntry,
                    spotifyLink: spotifyLink,
                    poll: poll,
                    backgroundMusic: nil,
                    mentionedUserIds: mentionedUserIds,
                    resharedPostId: resharedPostId
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
    
    // MARK: - Audio Preview Playback Helpers
    
    private func startAudioPreview() {
        guard let url = audioRecordingURL else { return }
        do {
            if audioPreviewPlayer == nil || audioPreviewPlayer?.url != url {
                audioPreviewPlayer = try AVAudioPlayer(contentsOf: url)
            }
            let duration = recordingTime
            let clamped = max(0, min(audioPreviewTime, duration > 0 ? duration : 0))
            audioPreviewPlayer?.currentTime = clamped
            audioPreviewPlayer?.play()
            isAudioPreviewPlaying = true
            
            audioPreviewTimer?.invalidate()
            audioPreviewTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                guard let player = self.audioPreviewPlayer else {
                    timer.invalidate()
                    return
                }
                if self.isAudioPreviewPlaying {
                    if !self.isAudioPreviewScrubbing {
                        self.audioPreviewTime = player.currentTime
                    }
                    if self.recordingTime > 0, self.audioPreviewTime >= self.recordingTime {
                        self.stopAudioPreview()
                    }
                } else {
                    timer.invalidate()
                }
            }
        } catch {
            errorMessage = "Failed to play preview: \(error.localizedDescription)"
        }
    }
    
    private func pauseAudioPreview() {
        audioPreviewPlayer?.pause()
        isAudioPreviewPlaying = false
        audioPreviewTimer?.invalidate()
        audioPreviewTimer = nil
    }
    
    private func stopAudioPreview() {
        audioPreviewPlayer?.stop()
        isAudioPreviewPlaying = false
        audioPreviewTime = 0
        audioPreviewTimer?.invalidate()
        audioPreviewTimer = nil
        audioPreviewPlayer = nil
    }
    
    private func seekAudioPreview(to time: TimeInterval) {
        let duration = recordingTime
        let clamped = duration > 0 ? max(0, min(time, duration)) : max(0, time)
        audioPreviewPlayer?.currentTime = clamped
        audioPreviewTime = clamped
    }
}


private struct ImageFullScreenViewer: View {
    let images: [UIImage]
    private let startIndex: Int
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showTopBar: Bool = true

    init(images: [UIImage], startIndex: Int) {
        self.images = images
        self.startIndex = startIndex
        self._index = State(initialValue: max(0, min(startIndex, max(0, images.count - 1))))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if images.isEmpty {
                Text("No images")
                    .foregroundColor(.white)
            } else {
                TabView(selection: $index) {
                    ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                        GeometryReader { proxy in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .background(Color.black)
                                .ignoresSafeArea()
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showTopBar.toggle()
                                    }
                                }
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            }

            VStack(spacing: 0) {
                ZStack {
                    Text("Preview photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                    HStack {
                        Spacer(minLength: 0)
                        Button("Done") {
                            dismiss()
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .background(Color.black.ignoresSafeArea(edges: .top))

                Spacer()
            }
            .opacity(showTopBar ? 1 : 0)
            .allowsHitTesting(showTopBar)
        }
    }
}

private struct VideoFullScreenPlayer: View {
    let url: URL
    @State private var player: AVPlayer
    @Environment(\.dismiss) private var dismiss
    @State private var showTopBar: Bool = true

    init(url: URL) {
        self.url = url
        self._player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { player.play() }
                .onDisappear { player.pause() }
            
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTopBar.toggle()
                    }
                }

            VStack(spacing: 0) {
                ZStack {
                    Text("Preview video")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                    HStack {
                        Spacer(minLength: 0)
                        Button("Done") {
                            player.pause()
                            dismiss()
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .background(Color.black.ignoresSafeArea(edges: .top))

                Spacer()
            }
            .opacity(showTopBar ? 1 : 0)
            .allowsHitTesting(showTopBar)
        }
    }
}

private struct FullScreenPHPickerView: View {
    @Binding var isPresented: Bool
    let selectionLimit: Int
    let filter: PHPickerFilter
    let onResults: ([PHPickerResult]) -> Void

    var body: some View {
        PHPickerControllerRepresentable(selectionLimit: selectionLimit, filter: filter) { results in
            onResults(results)
            isPresented = false
        }
        .ignoresSafeArea()
    }
}

private struct PHPickerControllerRepresentable: UIViewControllerRepresentable {
    let selectionLimit: Int
    let filter: PHPickerFilter
    let onResults: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = filter
        configuration.selectionLimit = selectionLimit
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onResults: onResults)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onResults: ([PHPickerResult]) -> Void
        init(onResults: @escaping ([PHPickerResult]) -> Void) {
            self.onResults = onResults
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            onResults(results)
        }
    }
}

