import SwiftUI

struct TrackDetailView: View {
    let track: StudioTrackRecord
    let album: StudioAlbumRecord
    
    @State private var showPlayer = false
    @State private var showShare = false
    @State private var showVersions = false
    
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(track.title)
                        .font(.title2)
                        .bold()
                    
                    if let trackNumber = track.track_number {
                        Text("Track \(trackNumber)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let duration = track.duration {
                        Text(formatTime(duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section("Actions") {
                Button {
                    showPlayer = true
                } label: {
                    Label("Play & Edit", systemImage: "play.circle.fill")
                }
                
                Button {
                    showShare = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                
                Button {
                    showVersions = true
                } label: {
                    Label("Version History", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle("Track")
        .sheet(isPresented: $showPlayer) {
            AudioPlayerView(track: track)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShare) {
            ShareSheetView(resourceType: "track", resourceId: track.id)
        }
        .sheet(isPresented: $showVersions) {
            NavigationStack {
                VersionHistoryView(track: track)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showVersions = false
                            }
                        }
                    }
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

