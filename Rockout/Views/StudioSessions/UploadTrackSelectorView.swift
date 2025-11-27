import SwiftUI

struct UploadTrackSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: StudioSessionsViewModel

    @State private var selectedAlbum: StudioAlbumRecord?
    @State private var showAddTrack = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Select Album") {
                    Picker("Album", selection: $selectedAlbum) {
                        ForEach(vm.albums) { album in
                            Text(album.title).tag(Optional(album))
                        }
                    }
                }

                Button {
                    if selectedAlbum != nil {
                        showAddTrack = true
                    }
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(selectedAlbum == nil)
            }
            .navigationTitle("Upload Track")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddTrack) {
                if let album = selectedAlbum {
                    AddTrackView(album: album) { dismiss() }
                }
            }
        }
    }
}
