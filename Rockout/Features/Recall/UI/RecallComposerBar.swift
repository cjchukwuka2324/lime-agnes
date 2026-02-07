import SwiftUI
import PhotosUI

struct RecallComposerBar: View {
    @Binding var text: String
    let onImageSelected: (UIImage) -> Void
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
            
            // Text input
            TextField("Type a description...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.1))
                )
                .foregroundColor(.white)
                .lineLimit(1...5)
            
            // Send button
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(canSend ? Color(hex: "#1ED760") : .white.opacity(0.3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .photosPicker(isPresented: $showImagePicker, selection: $selectedItem, matching: .images)
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let newItem = newItem,
                   let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onImageSelected(image)
                }
            }
        }
    }
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}


















