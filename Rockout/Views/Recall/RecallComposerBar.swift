import SwiftUI
import PhotosUI

struct RecallComposerBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onImageSelected: (UIImage) -> Void
    let onVideoSelected: (URL) -> Void
    let onSend: () -> Void
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var showImagePicker = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Photo attach button
            Button {
                showImagePicker = true
            } label: {
                Image(systemName: "photo.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("Attach photo or video")
            .accessibilityHint("Double tap to select a photo or video to search")
            
            // Text input
            TextField("Type a description...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.1))
                )
                .foregroundColor(.white)
                .lineLimit(1...5)
                .accessibilityLabel("Text input, alternative to voice recording")
                .accessibilityHint("Type your query here instead of using voice. Press return to send.")
                .submitLabel(.send)
            
            // Send button
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(canSend ? Color(hex: "#1ED760") : .white.opacity(0.3))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
            .accessibilityHint("Double tap to send your text query")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .photosPicker(isPresented: $showImagePicker, selection: $selectedItem, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedItem) { _, newItem in
            Task {
                guard let newItem = newItem else { return }
                
                // Check if it's a video
                let supportedTypes = newItem.supportedContentTypes
                let isVideo = supportedTypes.contains { type in
                    type.conforms(to: .movie) || type.identifier == "public.movie" || type.identifier.contains("video")
                }
                
                if isVideo {
                    // Handle video
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        let tempDir = FileManager.default.temporaryDirectory
                        let videoURL = tempDir.appendingPathComponent("\(UUID().uuidString).mov")
                        try? data.write(to: videoURL)
                        onVideoSelected(videoURL)
                    }
                } else {
                    // Handle image
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        onImageSelected(image)
                    }
                }
            }
        }
    }
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

