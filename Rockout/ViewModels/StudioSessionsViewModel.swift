import Foundation
import SwiftUI

@MainActor
final class StudioSessionsViewModel: ObservableObject {
    
    // MARK: - Shared Instance
    
    static let shared = StudioSessionsViewModel()
    
    // MARK: - Initializer
    
    private init() {
        // Private initializer to enforce singleton pattern
    }

    // MARK: - Published Properties

    @Published var albums: [StudioAlbumRecord] = []
    @Published var sharedAlbums: [StudioAlbumRecord] = []
    @Published var collaborativeAlbums: [StudioAlbumRecord] = []
    @Published var discoverFeedAlbums: [StudioAlbumRecord] = []
    @Published var discoveredAlbums: [StudioAlbumRecord] = []
    @Published var tracks: [StudioTrackRecord] = []
    @Published var isLoadingAlbums = false
    @Published var isLoadingSharedAlbums = false
    @Published var isLoadingCollaborativeAlbums = false
    @Published var isLoadingDiscoverFeed = false
    @Published var isLoadingDiscoveredAlbums = false
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

    func createAlbum(title: String, artistName: String?, coverArtData: Data?, isPublic: Bool = false) {
        Task {
            isLoadingAlbums = true
            errorMessage = nil
            defer { isLoadingAlbums = false }

            do {
                let newAlbum = try await albumService.createAlbum(
                    title: title,
                    artistName: artistName,
                    coverArtData: coverArtData,
                    isPublic: isPublic
                )
                albums.insert(newAlbum, at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }


    // MARK: - Delete Album

    func deleteAlbum(_ album: StudioAlbumRecord, context: AlbumService.AlbumDeleteContext) {
        Task {
            do {
                try await albumService.deleteAlbum(album, context: context)
                
                // Remove from appropriate list based on context
                switch context {
                case .myAlbums:
                    albums.removeAll { $0.id == album.id }
                case .sharedWithYou:
                    sharedAlbums.removeAll { $0.id == album.id }
                case .collaborations:
                    collaborativeAlbums.removeAll { $0.id == album.id }
                    // If owner deleted, also remove from myAlbums
                    // (This is handled by the service, but we clean up local state)
                    albums.removeAll { $0.id == album.id }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    // MARK: - Delete Album (Legacy - auto-detects context)
    // Kept for backward compatibility, but prefers explicit context
    func deleteAlbum(_ album: StudioAlbumRecord) {
        // Try to determine context from which list it's in
        if albums.contains(where: { $0.id == album.id }) {
            deleteAlbum(album, context: .myAlbums)
        } else if sharedAlbums.contains(where: { $0.id == album.id }) {
            deleteAlbum(album, context: .sharedWithYou)
        } else if collaborativeAlbums.contains(where: { $0.id == album.id }) {
            deleteAlbum(album, context: .collaborations)
        } else {
            // Fallback: try to determine from ownership
            Task {
                do {
                    try await albumService.deleteAlbum(album)
                    // Remove from all lists
                    albums.removeAll { $0.id == album.id }
                    sharedAlbums.removeAll { $0.id == album.id }
                    collaborativeAlbums.removeAll { $0.id == album.id }
                } catch {
                    errorMessage = error.localizedDescription
                }
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
                // Reload tracks to get updated track numbers after renumbering
                // Use the UUID version of fetchTracks
                let updatedTracks = try await trackService.fetchTracks(for: track.album_id)
                tracks = updatedTracks
            } catch {
                errorMessage = error.localizedDescription
                // Fallback: just remove the deleted track if reload fails
                tracks.removeAll { $0.id == track.id }
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
                let (album, isCollaboration) = try await shareService.acceptSharedAlbum(shareToken: shareToken)
                
                // If upgrading from view-only to collaboration, remove from sharedAlbums
                if isCollaboration {
                    // Remove from sharedAlbums if it exists there (upgrade scenario)
                    sharedAlbums.removeAll { $0.id == album.id }
                    // Add to collaborativeAlbums
                    if !collaborativeAlbums.contains(where: { $0.id == album.id }) {
                        collaborativeAlbums.insert(album, at: 0)
                    }
                } else {
                    // Remove from collaborativeAlbums if it exists there (downgrade scenario)
                    collaborativeAlbums.removeAll { $0.id == album.id }
                    // Add to sharedAlbums
                    if !sharedAlbums.contains(where: { $0.id == album.id }) {
                        sharedAlbums.insert(album, at: 0)
                    }
                }
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
    
    // MARK: - Discover Feed
    
    func loadDiscoverFeedAlbums(limit: Int = 50) {
        Task {
            isLoadingDiscoverFeed = true
            errorMessage = nil
            defer { isLoadingDiscoverFeed = false }
            
            do {
                let result = try await albumService.fetchDiscoverFeedAlbums(limit: limit)
                discoverFeedAlbums = result
                print("✅ Loaded \(result.count) discover feed albums")
            } catch {
                errorMessage = error.localizedDescription
                print("❌ Error loading discover feed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Discovered Albums (Saved)
    
    func loadDiscoveredAlbums() async {
        isLoadingDiscoveredAlbums = true
        errorMessage = nil
        defer { isLoadingDiscoveredAlbums = false }
        
        do {
            let result = try await albumService.getDiscoveredAlbums()
            discoveredAlbums = result
            print("✅ Loaded \(result.count) discovered albums")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading discovered albums: \(error.localizedDescription)")
        }
    }
    
    func saveDiscoveredAlbum(_ album: StudioAlbumRecord) async {
        do {
            try await albumService.saveDiscoveredAlbum(albumId: album.id)
            // Reload discovered albums to ensure state is accurate
            await loadDiscoveredAlbums()
            print("✅ Album saved to discoveries")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error saving discovered album: \(error.localizedDescription)")
            // Don't throw - errors are handled via errorMessage
        }
    }
    
    func removeDiscoveredAlbum(_ album: StudioAlbumRecord) async {
        do {
            try await albumService.removeDiscoveredAlbum(albumId: album.id)
            // Reload discovered albums to ensure state is accurate
            await loadDiscoveredAlbums()
            print("✅ Album removed from discoveries")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error removing discovered album: \(error.localizedDescription)")
            // Don't throw - errors are handled via errorMessage
        }
    }
    
    func isAlbumSaved(_ album: StudioAlbumRecord) -> Bool {
        return discoveredAlbums.contains(where: { $0.id == album.id })
    }
}
