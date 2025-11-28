import SwiftUI
import UniformTypeIdentifiers

struct AddTrackView: View {
    let album: StudioAlbumRecord
    let onUploaded: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var trackNumber: String = ""
    @State private var importedFile: ImportedFile?
    @State private var existingTracksCount: Int = 0

    @State private var showFilePicker = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var uploadProgress: Double = 0

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header Icon
                    headerIcon
                        .padding(.top, 20)
                    
                    // Track Info Section
                    trackInfoSection
                        .padding(.horizontal, 20)
                    
                    // Audio File Section
                    audioFileSection
                        .padding(.horizontal, 20)
                    
                    // Error Message
                    if let error = errorMessage {
                        errorView(error)
                            .padding(.horizontal, 20)
                    }
                    
                    // Upload Button
                    uploadButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Add Track")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            // Ensure navigation bar is always opaque
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .black
            appearance.shadowColor = .clear
            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .task {
            await loadExistingTracksCount()
        }
    }
    
    // MARK: - Header Icon
    private var headerIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 80, height: 80)
            
            Image(systemName: "music.note")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Track Info Section
    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Track Info")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 16) {
                // Track Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Track Title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                    
                    TextField("Enter track title", text: $title)
                        .textFieldStyle(CustomTextFieldStyle())
                }
                
                // Track Number
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Track Number")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        if existingTracksCount > 0 {
                            Text("(Current: \(existingTracksCount) tracks)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    
                    TextField("Enter position (1-\(max(1, existingTracksCount + 1)))", text: $trackNumber)
                        .keyboardType(.numberPad)
                        .textFieldStyle(CustomTextFieldStyle())
                    
                    Text("Leave empty to add at the end")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Audio File Section
    private var audioFileSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Audio File")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            
            if let importedFile {
                // Selected File Display
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "waveform")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(importedFile.filename)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let fileSize = formatFileSize(importedFile.data.count) {
                            Text(fileSize)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        self.importedFile = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                )
            } else {
                // Select File Button
                Button {
                    showFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .font(.title3)
                        Text("Select Audio File")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    // MARK: - Upload Button
    private var uploadButton: some View {
        Button {
            Task {
                await uploadTrack()
            }
        } label: {
            HStack {
                if isUploading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.headline)
                }
                Text(isUploading ? "Uploading..." : "Upload Track")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if canUpload && !isUploading {
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.gray.opacity(0.3)
                    }
                }
            )
            .cornerRadius(16)
        }
        .disabled(!canUpload || isUploading)
    }
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.2))
        )
    }
    
    // MARK: - Computed Properties
    private var canUpload: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        importedFile != nil &&
        !isUploading
    }
    
    private var parsedTrackNumber: Int? {
        guard !trackNumber.isEmpty,
              let number = Int(trackNumber),
              number > 0 else {
            return nil
        }
        return number
    }
    
    // MARK: - Helper Functions
    private func formatFileSize(_ bytes: Int) -> String? {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    private func loadExistingTracksCount() async {
        do {
            let tracks = try await TrackService.shared.fetchTracks(for: album.id)
            await MainActor.run {
                existingTracksCount = tracks.count
            }
        } catch {
            print("⚠️ Failed to load existing tracks count: \(error.localizedDescription)")
        }
    }
    
    // MARK: - File Import Handling
    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let file = try UniversalFileImportService.handle(result: result)
            importedFile = file
            errorMessage = nil
            print("Imported file:", file.filename, "at", file.sandboxURL)
        } catch let err as FileImportError {
            errorMessage = err.errorDescription
            importedFile = nil
        } catch {
            errorMessage = error.localizedDescription
            importedFile = nil
        }
    }
    
    // MARK: - Upload Logic
    private func uploadTrack() async {
        guard let importedFile else { return }

        isUploading = true
        errorMessage = nil
        uploadProgress = 0

        do {
            let data = importedFile.data

            _ = try await TrackService.shared.addTrack(
                to: album,
                title: title,
                audioData: data,
                duration: nil,
                trackNumber: parsedTrackNumber
            )

            await MainActor.run {
                isUploading = false
                onUploaded()
                dismiss()
            }

        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isUploading = false
            }
        }
    }
}

// MARK: - Custom Text Field Style
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
            .foregroundColor(.white)
    }
}
