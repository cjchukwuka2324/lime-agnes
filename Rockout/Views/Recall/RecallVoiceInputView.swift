import SwiftUI
import AVFoundation
import Supabase

public struct RecallVoiceInputView: View {
    let onRecallCreated: (UUID) -> Void
    
    public init(onRecallCreated: @escaping (UUID) -> Void) {
        self.onRecallCreated = onRecallCreated
    }
    
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var isUploading = false
    @State private var errorMessage: String?
    
    private let service = RecallService.shared
    private var recordingTimer: Timer?
    
    public var body: some View {
        VStack(spacing: 20) {
            // Recording button
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isRecording ? Color.red : Color(hex: "#1ED760"))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white)
                }
            }
            .disabled(isUploading)
            
            // Recording time
            if isRecording {
                Text(formatTime(recordingTime))
                    .font(.title2.monospacedDigit())
                    .foregroundColor(.white)
            }
            
            // Upload button (if recording exists)
            if let recordingURL = recordingURL, !isRecording {
                Button {
                    Task {
                        await uploadAndCreateRecall()
                    }
                } label: {
                    if isUploading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Find Song")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "#1ED760"))
                        )
                    }
                }
                .disabled(isUploading)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .onDisappear {
            if isRecording {
                stopRecording()
            }
        }
    }
    
    private func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recall_recording_\(UUID().uuidString).m4a")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordingTime = 0
            errorMessage = nil
            
            // Start timer
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                if isRecording {
                    recordingTime += 0.1
                } else {
                    timer.invalidate()
                }
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false)
        
        if let recorder = audioRecorder {
            recordingURL = recorder.url
        }
    }
    
    private func uploadAndCreateRecall() async {
        guard let recordingURL = recordingURL else { return }
        
        isUploading = true
        errorMessage = nil
        defer { isUploading = false }
        
        do {
            // Read audio data
            let audioData = try Data(contentsOf: recordingURL)
            
            // Create recall first to get ID
            let recallId = try await service.createRecall(inputType: .voice)
            
            // Upload audio
            let mediaPath = try await service.uploadMedia(
                data: audioData,
                recallId: recallId,
                fileName: "voice.m4a",
                contentType: "audio/m4a"
            )
            
            // Update recall event with media_path via direct database update
            let supabase = SupabaseService.shared.client
            try await supabase
                .from("recall_events")
                .update(["media_path": mediaPath])
                .eq("id", value: recallId.uuidString)
                .execute()
            
            // Start processing
            try await service.processRecall(recallId: recallId)
            
            // Clean up local file
            try? FileManager.default.removeItem(at: recordingURL)
            self.recordingURL = nil
            
            onRecallCreated(recallId)
        } catch {
            errorMessage = "Failed to upload: \(error.localizedDescription)"
            print("❌ RecallVoiceInputView.uploadAndCreateRecall error: \(error)")
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

