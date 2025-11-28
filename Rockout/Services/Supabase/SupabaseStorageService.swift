import Foundation
import Supabase

@MainActor
class SupabaseStorageService {
    static let shared = SupabaseStorageService()

    private let client = SupabaseService.shared.client

    private init() {}

    // MARK: - Upload Audio (no FileOptions supported)
    func uploadAudio(
        data: Data,
        artistId: String,
        albumId: String,
        trackId: String
    ) async throws -> String {

        let path = "\(artistId)/\(albumId)/\(trackId).mp3"

        // Minimal signature – no fileOptions
        try await client.storage
            .from("audio-files")
            .upload(
                path: path,
                file: data
            )

        return path
    }

    // MARK: - Upload Cover Art (no FileOptions supported)
    func uploadCoverArt(
        data: Data,
        artistId: String,
        albumId: String
    ) async throws -> String {

        let path = "\(artistId)/\(albumId)/cover.jpg"

        try await client.storage
            .from("album-cover-art")
            .upload(
                path: path,
                file: data
            )

        return path
    }

    // MARK: - Signed URL for audio
    func createSignedAudioURL(
        artistId: String,
        albumId: String,
        trackId: String,
        expiresIn seconds: Int = 3600
    ) async throws -> URL {

        let path = "\(artistId)/\(albumId)/\(trackId).mp3"

        let signedURL: URL = try await client.storage
            .from("audio-files")
            .createSignedURL(
                path: path,
                expiresIn: seconds
            )

        return signedURL
    }

    // MARK: - Signed URL for cover art
    func createSignedCoverArtURL(
        artistId: String,
        albumId: String,
        expiresIn seconds: Int = 3600
    ) async throws -> URL {

        let path = "\(artistId)/\(albumId)/cover.jpg"

        let signedURL: URL = try await client.storage
            .from("album-cover-art")
            .createSignedURL(
                path: path,
                expiresIn: seconds
            )

        return signedURL
    }
}
