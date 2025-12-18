import SwiftUI
import Vision
import VisionKit

struct RecallImageInputView: View {
    let onRecallCreated: (UUID) -> Void
    
    @State private var selectedImage: UIImage?
    @State private var ocrText: String = ""
    @State private var showImagePicker = false
    @State private var isProcessingOCR = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    
    private let service = RecallService.shared
    
    var body: some View {
        VStack(spacing: 16) {
            if let image = selectedImage {
                // Image preview
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                
                // OCR text (editable)
                if isProcessingOCR {
                    ProgressView("Extracting text...")
                        .tint(.white)
                } else if !ocrText.isEmpty {
                    TextField("Extracted text (editable)", text: $ocrText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.15))
                        )
                        .foregroundColor(.white)
                        .tint(Color(hex: "#1ED760"))
                        .lineLimit(3...6)
                }
                
                // Upload button
                Button {
                    Task {
                        await uploadAndCreateRecall()
                    }
                } label: {
                    if isUploading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Find Song")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canCreate ? Color(hex: "#1ED760") : Color.gray.opacity(0.3))
                        )
                    }
                }
                .disabled(!canCreate || isUploading)
            } else {
                // Image picker button
                Button {
                    showImagePicker = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.7))
                        Text("Select Image")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
                            )
                    )
                }
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                performOCR(on: image)
            }
        }
    }
    
    private var canCreate: Bool {
        !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func performOCR(on image: UIImage) {
        isProcessingOCR = true
        errorMessage = nil
        
        guard let cgImage = image.cgImage else {
            errorMessage = "Failed to process image"
            isProcessingOCR = false
            return
        }
        
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "OCR failed: \(error.localizedDescription)"
                    self.isProcessingOCR = false
                }
                return
            }
            
            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            
            DispatchQueue.main.async {
                self.ocrText = recognizedStrings.joined(separator: " ")
                self.isProcessingOCR = false
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "OCR failed: \(error.localizedDescription)"
                    self.isProcessingOCR = false
                }
            }
        }
    }
    
    private func uploadAndCreateRecall() async {
        guard let image = selectedImage, canCreate else { return }
        
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        
        do {
            // Create recall first to get ID
            let recallId = try await service.createRecall(
                inputType: .image,
                rawText: ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            // Upload image (optional, for "Ask the Crowd")
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                let mediaPath = try await service.uploadMedia(
                    data: imageData,
                    recallId: recallId,
                    fileName: "image.jpg",
                    contentType: "image/jpeg"
                )
                
                // Update recall event with media_path
                let supabase = SupabaseService.shared.client
                try await supabase
                    .from("recall_events")
                    .update(["media_path": mediaPath])
                    .eq("id", value: recallId.uuidString)
                    .execute()
            }
            
            // Start processing
            try await service.processRecall(recallId: recallId)
            
            onRecallCreated(recallId)
        } catch {
            errorMessage = "Failed to create recall: \(error.localizedDescription)"
            print("❌ RecallImageInputView.uploadAndCreateRecall error: \(error)")
        }
    }
}

