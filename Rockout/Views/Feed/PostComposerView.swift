import SwiftUI
import PhotosUI
import AVFoundation
import AVKit
import UniformTypeIdentifiers

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
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedVideo: URL?
    @State private var audioRecordingURL: URL?
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var isUploadingMedia = false
    @State private var showVideoPicker = false
    
    private let imageService = FeedImageService.shared
    private let mediaService = FeedMediaService.shared
    
    init(
        service: FeedService = InMemoryFeedService.shared,
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
                // Green gradient background
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
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Leaderboard Attachment Preview
                        if let entry = leaderboardEntry {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Sharing")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                LeaderboardAttachmentView(entry: entry)
                            }
                            .padding(.top, 20)
                        }
                        
                        // Media Previews
                        if let selectedImage = selectedImage {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Photo")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    Spacer()
                                    Button {
                                        self.selectedImage = nil
                                        self.selectedPhoto = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        
                        if let selectedVideo = selectedVideo {
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
                                    Text(selectedVideo.lastPathComponent)
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
                        
                        if let audioRecordingURL = audioRecordingURL {
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
                        
                        // Text Editor
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
                        
                        // Media Attachment Buttons Row
                        HStack(spacing: 12) {
                            // Photo Button
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.fill")
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
                            
                            // Video Button
                            Button {
                                showVideoPicker = true
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "video.fill")
                                        .font(.title3)
                                    Text("Video")
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
                            
                            // Voice Recording Button
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
                            .disabled(isPosting || isUploadingMedia || selectedPhoto != nil || selectedVideo != nil)
                        }
                        .padding(.vertical, 8)
                        
                        // Error Message
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal)
                        }
                        
                        Spacer()
                    }
                    .padding(20)
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
            .fileImporter(
                isPresented: $showVideoPicker,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                handleVideoImport(result)
            }
            .onChange(of: selectedPhoto) { _, newItem in
                if let item = newItem {
                    Task {
                        await loadImage(from: item)
                    }
                }
            }
        }
    }
    
    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
        selectedImage != nil || 
        selectedVideo != nil || 
        audioRecordingURL != nil
    }
    
    private func loadImage(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                selectedImage = image
            }
        } catch {
            errorMessage = "Failed to load image: \(error.localizedDescription)"
        }
    }
    
    private func handleVideoImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            if let videoURL = urls.first {
                // Check video duration - must be 1 minute (60 seconds) or less
                Task {
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
                            selectedVideo = videoURL
                            errorMessage = nil
                        }
                    }
                }
            }
        } catch {
            errorMessage = "Failed to import video: \(error.localizedDescription)"
        }
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
    
    private func post() async {
        guard canPost else { return }
        
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }
        
        do {
            // Upload media if selected
            var imageURL: URL? = nil
            var videoURL: URL? = nil
            var audioURL: URL? = nil
            
            if let image = selectedImage {
                isUploadingMedia = true
                imageURL = try await imageService.uploadPostImage(image)
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
            
            if let parentPost = parentPost {
                _ = try await service.reply(
                    to: parentPost,
                    text: postText,
                    imageURL: imageURL,
                    videoURL: videoURL,
                    audioURL: audioURL
                )
            } else {
                _ = try await service.createPost(
                    text: postText,
                    imageURL: imageURL,
                    videoURL: videoURL,
                    audioURL: audioURL,
                    leaderboardEntry: leaderboardEntry
                )
            }
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
