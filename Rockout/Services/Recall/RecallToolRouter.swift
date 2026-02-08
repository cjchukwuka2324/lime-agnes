import Foundation

/// Routes Voice Mode audio by type: speech → LLM/conversation; music/hum → audio recognition (recall-resolve).
/// Keeps RecallService.resolveRecall API unchanged.
@MainActor
final class RecallToolRouter {
    static let shared = RecallToolRouter()
    private let service = RecallService.shared

    private init() {}

    /// Resolve recall based on audio classification.
    /// - Parameters:
    ///   - threadId: Current thread
    ///   - messageId: User message ID (inserted by caller)
    ///   - audioType: Classification from AudioTypeClassifier
    ///   - text: For speech path — STT transcript. For music/hum — nil.
    ///   - mediaPath: For music/hum path — uploaded audio path. For speech — nil.
    func resolve(
        threadId: UUID,
        messageId: UUID,
        audioType: AudioClassificationType,
        text: String?,
        mediaPath: String?
    ) async throws -> RecallResolveResponse {
        switch audioType {
        case .speech:
            guard let transcript = text?.trimmingCharacters(in: .whitespacesAndNewlines), !transcript.isEmpty else {
                throw RecallToolRouterError.emptyTranscript
            }
            return try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .voice,
                text: transcript
            )
        case .music, .hum:
            guard let path = mediaPath else {
                throw RecallToolRouterError.missingMediaPath
            }
            return try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .voice,
                mediaPath: path
            )
        case .noise:
            throw RecallToolRouterError.noiseIgnored
        }
    }
}

enum RecallToolRouterError: LocalizedError {
    case emptyTranscript
    case missingMediaPath
    case noiseIgnored

    var errorDescription: String? {
        switch self {
        case .emptyTranscript: return "No transcript to process"
        case .missingMediaPath: return "No audio file for music/hum recognition"
        case .noiseIgnored: return "Noise classification ignored"
        }
    }
}
