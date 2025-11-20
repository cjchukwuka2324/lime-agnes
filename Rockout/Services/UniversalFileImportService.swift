import Foundation
import UniformTypeIdentifiers

struct ImportedFile {
    let data: Data
    let originalURL: URL
    let sandboxURL: URL
    let filename: String
    let fileExtension: String
}

enum FileImportError: LocalizedError {
    case noFileSelected
    case cannotCopyFromProvider
    case cannotReadData
    case unsupportedDRM
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .noFileSelected:
            return "No file was selected."
        case .cannotCopyFromProvider:
            return "This file is stored in another app and can’t be imported directly. Please move it into Files → iCloud Drive and select it again."
        case .cannotReadData:
            return "The file could not be read. It may be corrupted or restricted."
        case .unsupportedDRM:
            return "This audio file is DRM-protected and cannot be uploaded."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

enum UniversalFileImportService {

    /// Main universal handler – call this from `.fileImporter` completion.
    static func handle(result: Result<[URL], Error>) throws -> ImportedFile {
        do {
            guard let url = try result.get().first else {
                throw FileImportError.noFileSelected
            }

            // Try to gain security scope (works for Files, providers, etc.)
            let hasScope = url.startAccessingSecurityScopedResource()
            print("UniversalFileImportService: picked URL =", url)
            print("Security scope =", hasScope)

            defer {
                if hasScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // Create a sandbox temp URL with the same extension
            let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
            let filename = url.lastPathComponent

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)

            // Try to copy into our sandbox
            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
            } catch {
                // If copy fails, most likely provider or DRM blocked it
                let nsError = error as NSError
                print("copyItem error:", nsError)

                if nsError.domain == NSCocoaErrorDomain,
                   nsError.code == NSFileReadNoPermissionError {
                    throw FileImportError.cannotCopyFromProvider
                }

                throw FileImportError.underlying(error)
            }

            // Now read data from our own sandbox file
            do {
                let data = try Data(contentsOf: tempURL)
                return ImportedFile(
                    data: data,
                    originalURL: url,
                    sandboxURL: tempURL,
                    filename: filename,
                    fileExtension: ext
                )
            } catch {
                throw FileImportError.cannotReadData
            }

        } catch let error as FileImportError {
            throw error
        } catch {
            throw FileImportError.underlying(error)
        }
    }
}
