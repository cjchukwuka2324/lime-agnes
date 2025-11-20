import SwiftUI
import UniformTypeIdentifiers

struct AddTrackView: View {
    let album: StudioAlbumRecord
    let onUploaded: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var trackNumber: Int?
    @State private var importedFile: ImportedFile?

    @State private var showFilePicker = false
    @State private var isUploading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Track Info") {
                    TextField("Track Title", text: $title)

                    TextField("Track Number", value: $trackNumber, format: .number)
                        .keyboardType(.numberPad)
                }

                Section("Audio File") {
                    if let importedFile {
                        HStack {
                            Image(systemName: "waveform")
                            Text(importedFile.filename)
                                .lineLimit(1)
                        }
                    } else {
                        Text("No file selected")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Select Audio File", systemImage: "music.note")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Add Track")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await uploadTrack() }
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Upload").bold()
                        }
                    }
                    .disabled(!canUpload)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    private var canUpload: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        importedFile != nil &&
        !isUploading
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

        do {
            let data = importedFile.data

            _ = try await TrackService.shared.addTrack(
                to: album,
                title: title,
                audioData: data,
                duration: nil,           // you can compute with AVAsset later
                trackNumber: trackNumber
            )

            isUploading = false
            onUploaded()
            dismiss()

        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isUploading = false
            }
        }
    }
}
