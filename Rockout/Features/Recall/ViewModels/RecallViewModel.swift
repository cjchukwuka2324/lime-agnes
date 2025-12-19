import Foundation
import SwiftUI
import Combine

@MainActor
final class RecallViewModel: ObservableObject {
    @Published var currentThreadId: UUID?
    @Published var messages: [RecallMessage] = []
    @Published var composerText: String = ""
    @Published var orbState: RecallOrbState = .idle
    @Published var selectedImage: UIImage?
    @Published var isResolving: Bool = false
    @Published var errorMessage: String?
    
    private let service = RecallService.shared
    private let voiceRecorder = VoiceRecorder()
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Observe voice recorder state
        voiceRecorder.$isRecording
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if isRecording {
                    // State will be updated by meter level updates
                } else {
                    if case .listening = self.orbState {
                        // Recording stopped, will transition to thinking when upload starts
                    }
                }
            }
            .store(in: &cancellables)
        
        voiceRecorder.$meterLevel
            .sink { [weak self] level in
                guard let self = self else { return }
                if case .listening = self.orbState {
                    self.orbState = .listening(level: level)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Thread Management
    
    func startNewThreadIfNeeded() async {
        do {
            let threadId = try await service.createThreadIfNeeded()
            currentThreadId = threadId
            await loadMessages()
        } catch {
            errorMessage = "Failed to create thread: \(error.localizedDescription)"
            print("❌ Failed to create thread: \(error)")
        }
    }
    
    func loadMessages() async {
        guard let threadId = currentThreadId else { return }
        
        do {
            messages = try await service.fetchMessages(threadId: threadId)
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
            print("❌ Failed to load messages: \(error)")
        }
    }
    
    // MARK: - Send Text
    
    func sendText() async {
        guard let threadId = currentThreadId,
              !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        composerText = ""
        
        do {
            // Insert user message
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .text,
                text: text
            )
            
            // Reload messages
            await loadMessages()
            
            // Insert status message
            let statusMessageId = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching..."
            )
            
            await loadMessages()
            orbState = .thinking
            
            // Resolve
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .text,
                text: text
            )
            
            // Update status message with result
            if let assistantMessage = response.assistantMessage {
                let candidateJson: [String: AnyCodable] = [
                    "title": AnyCodable(assistantMessage.songTitle),
                    "artist": AnyCodable(assistantMessage.songArtist),
                    "confidence": AnyCodable(assistantMessage.confidence),
                    "reason": AnyCodable(assistantMessage.reason),
                    "lyric_snippet": AnyCodable(assistantMessage.lyricSnippet ?? "")
                ]
                
                // Update the status message to candidate
                // Note: In a real implementation, we'd update the existing message
                // For now, we'll insert a new candidate message
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .candidate,
                    text: "\(assistantMessage.songTitle) by \(assistantMessage.songArtist)",
                    candidateJson: candidateJson,
                    sourcesJson: assistantMessage.sources,
                    confidence: assistantMessage.confidence,
                    songUrl: assistantMessage.songUrl,
                    songTitle: assistantMessage.songTitle,
                    songArtist: assistantMessage.songArtist
                )
            }
            
            await loadMessages()
            
            // Update orb state based on confidence
            if let confidence = response.assistantMessage?.confidence {
                orbState = .done(confidence: confidence)
                
                // Reset to idle after 2 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                    }
                }
            } else {
                orbState = .error
            }
            
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            orbState = .error
            print("❌ Failed to send text: \(error)")
        }
    }
    
    // MARK: - Pick Image
    
    func pickImage(_ image: UIImage) async {
        selectedImage = image
        await sendImage()
    }
    
    private func sendImage() async {
        guard let threadId = currentThreadId,
              let image = selectedImage,
              let imageData = image.jpegData(compressionQuality: 0.7) else {
            return
        }
        
        selectedImage = nil
        
        do {
            // Compress and resize if needed
            let finalImage: UIImage
            if image.size.width > 1024 || image.size.height > 1024 {
                let maxDimension: CGFloat = 1024
                let ratio = min(maxDimension / image.size.width, maxDimension / image.size.height)
                let newSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                finalImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
            } else {
                finalImage = image
            }
            
            guard let finalData = finalImage.jpegData(compressionQuality: 0.7) else {
                throw NSError(domain: "RecallViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
            }
            
            // Upload
            let fileName = "image_\(Int(Date().timeIntervalSince1970)).jpg"
            let mediaPath = try await service.uploadMedia(
                data: finalData,
                threadId: threadId,
                fileName: fileName,
                contentType: "image/jpeg"
            )
            
            // Insert user message
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .image,
                mediaPath: mediaPath
            )
            
            await loadMessages()
            
            // Insert status message
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching..."
            )
            
            await loadMessages()
            orbState = .thinking
            
            // Resolve
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .image,
                mediaPath: mediaPath
            )
            
            // Update with candidate (same as text flow)
            if let assistantMessage = response.assistantMessage {
                let candidateJson: [String: AnyCodable] = [
                    "title": AnyCodable(assistantMessage.songTitle),
                    "artist": AnyCodable(assistantMessage.songArtist),
                    "confidence": AnyCodable(assistantMessage.confidence),
                    "reason": AnyCodable(assistantMessage.reason),
                    "lyric_snippet": AnyCodable(assistantMessage.lyricSnippet ?? "")
                ]
                
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .candidate,
                    text: "\(assistantMessage.songTitle) by \(assistantMessage.songArtist)",
                    candidateJson: candidateJson,
                    sourcesJson: assistantMessage.sources,
                    confidence: assistantMessage.confidence,
                    songUrl: assistantMessage.songUrl,
                    songTitle: assistantMessage.songTitle,
                    songArtist: assistantMessage.songArtist
                )
            }
            
            await loadMessages()
            
            if let confidence = response.assistantMessage?.confidence {
                orbState = .done(confidence: confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                    }
                }
            } else {
                orbState = .error
            }
            
        } catch {
            errorMessage = "Failed to send image: \(error.localizedDescription)"
            orbState = .error
            print("❌ Failed to send image: \(error)")
        }
    }
    
    // MARK: - Orb Tapped
    
    func orbTapped() async {
        if voiceRecorder.isRecording {
            // Stop recording
            voiceRecorder.stopRecording()
            await handleVoiceRecording()
        } else {
            // Start recording
            do {
                try await voiceRecorder.startRecording()
                orbState = .listening(level: 0.0)
            } catch {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                orbState = .error
                print("❌ Failed to start recording: \(error)")
            }
        }
    }
    
    private func handleVoiceRecording() async {
        guard let threadId = currentThreadId,
              let recordingURL = voiceRecorder.recordingURL else {
            orbState = .error
            return
        }
        
        orbState = .thinking
        
        do {
            // Read audio data
            let audioData = try Data(contentsOf: recordingURL)
            
            // Upload
            let fileName = "voice_\(Int(Date().timeIntervalSince1970)).m4a"
            let mediaPath = try await service.uploadMedia(
                data: audioData,
                threadId: threadId,
                fileName: fileName,
                contentType: "audio/m4a"
            )
            
            // Insert user message
            let messageId = try await service.insertMessage(
                threadId: threadId,
                role: .user,
                messageType: .voice,
                mediaPath: mediaPath
            )
            
            await loadMessages()
            
            // Insert status message
            _ = try await service.insertMessage(
                threadId: threadId,
                role: .assistant,
                messageType: .status,
                text: "Searching..."
            )
            
            await loadMessages()
            
            // Resolve
            let response = try await service.resolveRecall(
                threadId: threadId,
                messageId: messageId,
                inputType: .voice,
                mediaPath: mediaPath
            )
            
            // Update with candidate
            if let assistantMessage = response.assistantMessage {
                let candidateJson: [String: AnyCodable] = [
                    "title": AnyCodable(assistantMessage.songTitle),
                    "artist": AnyCodable(assistantMessage.songArtist),
                    "confidence": AnyCodable(assistantMessage.confidence),
                    "reason": AnyCodable(assistantMessage.reason),
                    "lyric_snippet": AnyCodable(assistantMessage.lyricSnippet ?? "")
                ]
                
                _ = try await service.insertMessage(
                    threadId: threadId,
                    role: .assistant,
                    messageType: .candidate,
                    text: "\(assistantMessage.songTitle) by \(assistantMessage.songArtist)",
                    candidateJson: candidateJson,
                    sourcesJson: assistantMessage.sources,
                    confidence: assistantMessage.confidence,
                    songUrl: assistantMessage.songUrl,
                    songTitle: assistantMessage.songTitle,
                    songArtist: assistantMessage.songArtist
                )
            }
            
            await loadMessages()
            
            if let confidence = response.assistantMessage?.confidence {
                orbState = .done(confidence: confidence)
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if case .done = orbState {
                        orbState = .idle
                    }
                }
            } else {
                orbState = .error
            }
            
            // Clean up recording file
            try? FileManager.default.removeItem(at: recordingURL)
            
        } catch {
            errorMessage = "Failed to process voice: \(error.localizedDescription)"
            orbState = .error
            print("❌ Failed to process voice: \(error)")
        }
    }
    
    // MARK: - Load Stash
    
    func loadStash() async -> [RecallStashItem] {
        do {
            return try await service.fetchStash()
        } catch {
            errorMessage = "Failed to load stash: \(error.localizedDescription)"
            print("❌ Failed to load stash: \(error)")
            return []
        }
    }
    
    // MARK: - Open Thread
    
    func openThread(threadId: UUID) async {
        currentThreadId = threadId
        await loadMessages()
    }
}








