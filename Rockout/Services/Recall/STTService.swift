import Foundation
import AVFoundation
import Speech

/// Streaming speech-to-text using SFSpeechRecognizer.
/// Receives audio buffers from AudioIOManager and emits partial/final transcripts.
@MainActor
final class STTService: ObservableObject {
    @Published var partialTranscript: String = ""
    @Published var finalTranscript: String = ""
    @Published var isRecognizing: Bool = false
    @Published var lastError: Error?

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasReceivedSpeech = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Authorization

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Recognition

    func startRecognition() throws {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw STTError.recognizerUnavailable
        }
        guard Self.isAuthorized else {
            throw STTError.notAuthorized
        }

        stopRecognition()

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        recognitionRequest.addsPunctuation = true

        request = recognitionRequest
        partialTranscript = ""
        finalTranscript = ""
        hasReceivedSpeech = false

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }

        isRecognizing = true
        Logger.recall.info("STTService: recognition started")
    }

    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func endAudio() {
        request?.endAudio()
        Logger.recall.debug("STTService: endAudio called")
    }

    func stopRecognition() {
        task?.cancel()
        task = nil
        request = nil
        isRecognizing = false
        Logger.recall.info("STTService: recognition stopped")
    }

    // MARK: - Handlers

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                return
            }
            lastError = error
            Logger.recall.error("STTService error: \(error.localizedDescription)")
            stopRecognition()
            return
        }

        guard let result = result else { return }

        let transcript = result.bestTranscription.formattedString
        if !transcript.isEmpty {
            hasReceivedSpeech = true
        }

        if result.isFinal {
            finalTranscript = transcript
            onFinalResult?(transcript)
            Logger.recall.debug("STTService final: \(transcript.prefix(50))...")
            stopRecognition()
        } else {
            partialTranscript = transcript
            onPartialResult?(transcript)
        }
    }
}

enum STTError: LocalizedError {
    case recognizerUnavailable
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is not available"
        case .notAuthorized:
            return "Speech recognition permission not granted"
        }
    }
}
