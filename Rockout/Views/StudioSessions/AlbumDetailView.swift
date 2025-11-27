import SwiftUI

struct AlbumDetailView: View {
    let album: StudioAlbumRecord

    @State private var tracks: [StudioTrackRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddTrack = false

    private let trackService = TrackService.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(album.title)
                        .font(.title2)
                        .bold()

                    if let status = album.release_status {
                        Text(status.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Tracks") {
                if isLoading {
                    ProgressView("Loading tracks...")
                } else if tracks.isEmpty {
                    Text("No tracks yet. Add one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tracks) { track in
                        VStack(alignment: .leading) {
                            Text(track.title)
                                .font(.headline)

                            if let n = track.track_number {
                                Text("Track \(n)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Album")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddTrack = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddTrack) {
            AddTrackView(album: album) {
                Task { await loadTracks() }
            }
        }
        .task {
            await loadTracks()
        }
    }

    private func loadTracks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            tracks = try await trackService.fetchTracks(for: album)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
