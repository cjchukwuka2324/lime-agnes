import SwiftUI

struct VersionHistoryView: View {
    let track: StudioTrackRecord
    
    @State private var versions: [TrackVersion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showReplaceAudio = false
    
    private let versionService = VersionService.shared
    
    var body: some View {
        List {
            Section {
                Button {
                    showReplaceAudio = true
                } label: {
                    Label("Replace Audio", systemImage: "arrow.clockwise")
                }
            }
            
            Section("Version History") {
                if isLoading {
                    ProgressView()
                } else if versions.isEmpty {
                    Text("No versions yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(versions) { version in
                        VersionRow(version: version) {
                            Task {
                                await restoreVersion(version)
                            }
                        }
                    }
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Version History")
        .task {
            await loadVersions()
        }
        .sheet(isPresented: $showReplaceAudio) {
            ReplaceAudioView(track: track) {
                Task {
                    await loadVersions()
                }
            }
        }
    }
    
    private func loadVersions() async {
        isLoading = true
        errorMessage = nil
        
        do {
            versions = try await versionService.getTrackVersions(for: track.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func restoreVersion(_ version: TrackVersion) async {
        do {
            try await versionService.restoreTrackVersion(version, to: track)
            await loadVersions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct VersionRow: View {
    let version: TrackVersion
    let onRestore: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Version \(version.version_number)")
                    .font(.headline)
                Spacer()
                Text(formatDate(version.created_at))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let notes = version.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                if let duration = version.duration {
                    Label(formatTime(duration), systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if let fileSize = version.file_size {
                    Label(formatFileSize(fileSize), systemImage: "doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                onRestore()
            } label: {
                Text("Restore This Version")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ReplaceAudioView: View {
    let track: StudioTrackRecord
    let onReplaced: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var importedFile: ImportedFile?
    @State private var showFilePicker = false
    @State private var isUploading = false
    @State private var notes: String = ""
    @State private var errorMessage: String?
    
    private let versionService = VersionService.shared
    
    var body: some View {
        NavigationStack {
            Form {
                Section("New Audio File") {
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
                
                Section("Notes (Optional)") {
                    TextField("e.g., Added vocals, mixed differently", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Replace Audio")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await replaceAudio()
                        }
                    } label: {
                        if isUploading {
                            ProgressView()
                        } else {
                            Text("Replace").bold()
                        }
                    }
                    .disabled(importedFile == nil || isUploading)
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
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let file = try UniversalFileImportService.handle(result: result)
            importedFile = file
            errorMessage = nil
        } catch let err as FileImportError {
            errorMessage = err.errorDescription
            importedFile = nil
        } catch {
            errorMessage = error.localizedDescription
            importedFile = nil
        }
    }
    
    private func replaceAudio() async {
        guard let importedFile else { return }
        
        isUploading = true
        errorMessage = nil
        
        do {
            _ = try await versionService.createTrackVersion(
                for: track,
                audioData: importedFile.data,
                notes: notes.isEmpty ? nil : notes,
                duration: nil // Could calculate with AVAsset
            )
            
            isUploading = false
            onReplaced()
            dismiss()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isUploading = false
            }
        }
    }
}

