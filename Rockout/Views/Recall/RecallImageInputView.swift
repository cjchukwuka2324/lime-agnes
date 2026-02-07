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
        let requestId = UUID().uuidString.prefix(8)
        let startTime = Date()
        
        print("🔍 [RECALL-IMAGE] [\(requestId)] performOCR() started")
        isProcessingOCR = true
        errorMessage = nil
        
        guard let cgImage = image.cgImage else {
            print("❌ [RECALL-IMAGE] [\(requestId)] Failed to get CGImage from UIImage")
            errorMessage = "Failed to process image"
            isProcessingOCR = false
            return
        }
        
        let imageSize = image.size
        let imageScale = image.scale
        print("📊 [RECALL-IMAGE] [\(requestId)] Image info: size=\(imageSize.width)x\(imageSize.height), scale=\(imageScale)")
        
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                let duration = Date().timeIntervalSince(startTime)
                print("❌ [RECALL-IMAGE] [\(requestId)] OCR failed after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
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
            
            let ocrResult = recognizedStrings.joined(separator: " ")
            let duration = Date().timeIntervalSince(startTime)
            print("✅ [RECALL-IMAGE] [\(requestId)] OCR completed in \(String(format: "%.3f", duration))s")
            print("📝 [RECALL-IMAGE] [\(requestId)] OCR result: \(observations.count) observations, \(ocrResult.count) chars")
            print("   Text: \"\(ocrResult.prefix(200))\(ocrResult.count > 200 ? "..." : "")\"")
            
            DispatchQueue.main.async {
                self.ocrText = ocrResult
                self.isProcessingOCR = false
            }
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                print("🔧 [RECALL-IMAGE] [\(requestId)] Starting OCR processing...")
                try handler.perform([request])
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                print("❌ [RECALL-IMAGE] [\(requestId)] OCR handler.perform() failed after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "OCR failed: \(error.localizedDescription)"
                    self.isProcessingOCR = false
                }
            }
        }
    }
    
    private func uploadAndCreateRecall() async {
        let requestId = UUID().uuidString.prefix(8)
        let startTime = Date()
        
        guard let image = selectedImage, canCreate else {
            print("⚠️ [RECALL-IMAGE] [\(requestId)] Cannot create recall: image=\(selectedImage != nil), canCreate=\(canCreate)")
            return
        }
        
        print("🔍 [RECALL-IMAGE] [\(requestId)] uploadAndCreateRecall() started")
        print("📊 [RECALL-IMAGE] [\(requestId)] OCR text length: \(ocrText.count) chars")
        print("   OCR text: \"\(ocrText.prefix(200))\(ocrText.count > 200 ? "..." : "")\"")
        
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        
        do {
            // Create recall first to get ID
            let createStartTime = Date()
            print("📤 [RECALL-IMAGE] [\(requestId)] Creating recall with OCR text...")
            let recallId = try await service.createRecall(
                inputType: .image,
                rawText: ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let createDuration = Date().timeIntervalSince(createStartTime)
            print("✅ [RECALL-IMAGE] [\(requestId)] Recall created in \(String(format: "%.3f", createDuration))s: \(recallId.uuidString)")
            
            // Upload image (optional, for "Ask the Crowd")
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                let uploadStartTime = Date()
                let imageSize = imageData.count
                print("📤 [RECALL-IMAGE] [\(requestId)] Uploading image: \(imageSize) bytes")
                let mediaPath = try await service.uploadMedia(
                    data: imageData,
                    recallId: recallId,
                    fileName: "image.jpg",
                    contentType: "image/jpeg"
                )
                let uploadDuration = Date().timeIntervalSince(uploadStartTime)
                print("✅ [RECALL-IMAGE] [\(requestId)] Image uploaded in \(String(format: "%.3f", uploadDuration))s: \(mediaPath)")
                
                // Update recall event with media_path
                let updateStartTime = Date()
                let supabase = SupabaseService.shared.client
                try await supabase
                    .from("recall_events")
                    .update(["media_path": mediaPath])
                    .eq("id", value: recallId.uuidString)
                    .execute()
                let updateDuration = Date().timeIntervalSince(updateStartTime)
                print("✅ [RECALL-IMAGE] [\(requestId)] Recall event updated in \(String(format: "%.3f", updateDuration))s")
            } else {
                print("⚠️ [RECALL-IMAGE] [\(requestId)] Could not convert image to JPEG data")
            }
            
            // Start processing
            let processStartTime = Date()
            print("🔍 [RECALL-IMAGE] [\(requestId)] Starting recall processing...")
            try await service.processRecall(recallId: recallId)
            let processDuration = Date().timeIntervalSince(processStartTime)
            print("✅ [RECALL-IMAGE] [\(requestId)] Recall processing started in \(String(format: "%.3f", processDuration))s")
            
            let totalDuration = Date().timeIntervalSince(startTime)
            print("✅ [RECALL-IMAGE] [\(requestId)] uploadAndCreateRecall() completed successfully in \(String(format: "%.3f", totalDuration))s")
            
            onRecallCreated(recallId)
        } catch {
            let totalDuration = Date().timeIntervalSince(startTime)
            errorMessage = "Failed to create recall: \(error.localizedDescription)"
            print("❌ [RECALL-IMAGE] [\(requestId)] uploadAndCreateRecall() failed after \(String(format: "%.3f", totalDuration))s: \(error.localizedDescription)")
            if let nsError = error as? NSError {
                print("   Error code: \(nsError.code), domain: \(nsError.domain)")
            }
        }
    }
}

