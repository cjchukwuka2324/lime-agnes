import Foundation
import SwiftUI

@MainActor
final class StudioSessionsViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var albums: [StudioAlbumRecord] = []
    @Published var sharedAlbums: [StudioAlbumRecord] = []
    @Published var collaborativeAlbums: [StudioAlbumRecord] = []
    @Published var tracks: [StudioTrackRecord] = []
    @Published var isLoadingAlbums = false
    @Published var isLoadingSharedAlbums = false
    @Published var isLoadingCollaborativeAlbums = false
    @Published var isLoadingTracks = false
    @Published var errorMessage: String?

    private let albumService = AlbumService.shared
    private let trackService = TrackService.shared
    private let shareService = ShareService.shared


    // MARK: - Load Albums

    func loadAlbums() {
        Task {
            isLoadingAlbums = true
            errorMessage = nil
            defer { isLoadingAlbums = false }

            do {
                let result = try await albumService.fetchMyAlbums()
                albums = result
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }


    // MARK: - Create Album With Optional Cover Art

    func createAlbum(title: String, artistName: String?, coverArtData: Data?) {
        Task {
            isLoadingAlbums = true
            errorMessage = nil
            defer { isLoadingAlbums = false }

            do {
                let newAlbum = try await albumService.createAlbum(
                    title: title,
                    artistName: artistName,
                    coverArtData: coverArtData
                )
                albums.insert(newAlbum, at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }


    // MARK: - Delete Album

    func deleteAlbum(_ album: StudioAlbumRecord) {
        Task {
            do {
                try await albumService.deleteAlbum(album)
                albums.removeAll { $0.id == album.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }


    // MARK: - Load Tracks For Album

    func loadTracks(for album: StudioAlbumRecord) {
        Task {
            isLoadingTracks = true
            errorMessage = nil
            tracks = []
            defer { isLoadingTracks = false }

            do {
                let result = try await trackService.fetchTracks(for: album)
                tracks = result
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }


    // MARK: - Delete Track

    func deleteTrack(_ track: StudioTrackRecord) {
        Task {
            do {
                try await trackService.deleteTrack(track)
                tracks.removeAll { $0.id == track.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Load Shared Albums
    
    func loadSharedAlbums() async {
        isLoadingSharedAlbums = true
        errorMessage = nil
        defer { isLoadingSharedAlbums = false }
        
        do {
            let result = try await albumService.fetchSharedAlbums()
            sharedAlbums = result
            print("✅ Loaded \(result.count) shared album(s)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading shared albums: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Accept Shared Album
    
    func acceptSharedAlbum(shareToken: String) {
        Task {
            isLoadingSharedAlbums = true
            errorMessage = nil
            defer { isLoadingSharedAlbums = false }
            
            do {
                let album = try await shareService.acceptSharedAlbum(shareToken: shareToken)
                sharedAlbums.insert(album, at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Load Collaborative Albums
    
    func loadCollaborativeAlbums() async {
        isLoadingCollaborativeAlbums = true
        errorMessage = nil
        defer { isLoadingCollaborativeAlbums = false }
        
        do {
            let result = try await albumService.fetchCollaborativeAlbums()
            collaborativeAlbums = result
            print("✅ Loaded \(result.count) collaborative album(s)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading collaborative albums: \(error.localizedDescription)")
        }
    }
}
