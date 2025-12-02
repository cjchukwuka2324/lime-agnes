import SwiftUI
import PhotosUI

struct MultiImagePicker: View {
    @Binding var selectedImages: [UIImage]
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    
    private let maxSelectionCount = 4
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading images...")
                        .padding()
                }
                
                if !selectedImages.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                            ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    Button {
                                        selectedImages.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                    .padding(4)
                                }
                            }
                        }
                        .padding()
                    }
                }
                
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: maxSelectionCount,
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                        Text("Select Photos (\(selectedImages.count)/\(maxSelectionCount))")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "#1ED760"))
                    )
                    .padding(.horizontal)
                }
                .disabled(selectedImages.count >= maxSelectionCount)
                
                Spacer()
            }
            .navigationTitle("Select Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(selectedImages.isEmpty)
                }
            }
            .onChange(of: selectedItems) { _, newItems in
                Task {
                    await loadImages(from: newItems)
                }
            }
        }
    }
    
    private func loadImages(from items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }
        
        // Clear previous images when new selection is made
        selectedImages.removeAll()
        
        for item in items {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        if selectedImages.count < maxSelectionCount {
                            selectedImages.append(image)
                        }
                    }
                }
            } catch {
                print("Failed to load image: \(error.localizedDescription)")
            }
        }
    }
}

