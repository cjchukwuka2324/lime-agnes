import SwiftUI

struct StudioSessionsView: View {
    @StateObject private var viewModel = StudioSessionsViewModel()

    @State private var newAlbumTitle = ""
    @State private var showCreateAlbumSheet = false
    @State private var coverArtImage: UIImage?
    @State private var showImagePicker = false

    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.isLoadingAlbums {
                    ProgressView().padding()
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }

                List {
                    ForEach(viewModel.albums, id: \.id) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            HStack {

                                // COVER IMAGE
                                if let urlString = album.cover_art_url,
                                   let url = URL(string: urlString) {
                                    AsyncImage(url: url) { img in
                                        img.resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                    }
                                    .frame(width: 60, height: 60)
                                    .cornerRadius(8)
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                }

                                VStack(alignment: .leading) {
                                    Text(album.title)
                                        .font(.headline)

                                    // FIXED: release_status IS OPTIONAL
                                    Text((album.release_status ?? "").capitalized)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { idx in
                            let album = viewModel.albums[idx]
                            viewModel.deleteAlbum(album)
                        }
                    }
                }
            }
            .navigationTitle("Studio Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateAlbumSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateAlbumSheet) {
                createAlbumSheet
            }
            .onAppear {
                viewModel.loadAlbums()
            }
        }
    }

    private var createAlbumSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Album Title")) {
                    TextField("Enter title", text: $newAlbumTitle)
                }

                Section(header: Text("Cover Art")) {
                    if let image = coverArtImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 150)
                            .cornerRadius(12)
                    }

                    Button("Choose Image") {
                        showImagePicker = true
                    }
                }
            }
            .navigationTitle("New Album")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        resetAlbumCreation()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        let imageData = coverArtImage?.jpegData(compressionQuality: 0.8)
                        viewModel.createAlbum(title: newAlbumTitle, coverArtData: imageData)
                        resetAlbumCreation()
                    }
                    .disabled(newAlbumTitle.isEmpty)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $coverArtImage)
            }
        }
    }

    private func resetAlbumCreation() {
        newAlbumTitle = ""
        coverArtImage = nil
        showCreateAlbumSheet = false
    }
}
