import SwiftUI
import PhotosUI

struct CreateAlbumView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: StudioSessionsViewModel

    @State private var title: String = ""
    @State private var artistName: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverImage: UIImage?
    @State private var isSaving = false
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Album Info") {
                    TextField("Album title", text: $title)
                    TextField("Artist name (optional)", text: $artistName)
                        .autocapitalization(.words)
                }

                Section("Cover Art (optional)") {
                    HStack(spacing: 16) {
                        if let image = coverImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 64, height: 64)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                )
                        }

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Text(coverImage == nil ? "Select cover image" : "Change cover image")
                        }
                    }
                }

                if let error = localError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Create Album")
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAlbum() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Create")
                                .bold()
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                if let item = newValue {
                    Task { await loadImage(from: item) }
                }
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                self.coverImage = image
            }
        } catch {
            localError = "Failed to load image."
        }
    }

    private func saveAlbum() async {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSaving = true
        localError = nil

        do {
            var coverData: Data? = nil
            if let img = coverImage {
                coverData = img.jpegData(compressionQuality: 0.9)
            }

            let artistNameValue = artistName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : artistName.trimmingCharacters(in: .whitespaces)
            await vm.createAlbum(title: title, artistName: artistNameValue, coverArtData: coverData)
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            localError = error.localizedDescription
        }
    }
}
