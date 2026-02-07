import SwiftUI

struct RecallLiveTranscriptView: View {
    let transcript: String
    let isRecording: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .accessibilityHidden(true)
                Text("Live Transcript:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            HStack(alignment: .top, spacing: 4) {
                Text(transcript.isEmpty ? "Listening..." : transcript)
                    .font(.body)
                    .foregroundColor(.white)
                    .italic()
                    .lineLimit(3)
                    .accessibilityLabel(transcript.isEmpty ? "Listening" : transcript)
                
                if isRecording && !transcript.isEmpty {
                    // Pulsing cursor
                    Text("|")
                        .font(.body)
                        .foregroundColor(Color(hex: "#1ED760"))
                        .opacity(pulsingOpacity)
                        .animation(
                            Animation.easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true),
                            value: pulsingOpacity
                        )
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
        .accessibilityLabel("Live transcript")
        .accessibilityValue(transcript.isEmpty ? "Listening" : transcript)
        .accessibilityHint(isRecording ? "Live transcription of your voice input" : "Final transcription")
    }
    
    @State private var pulsingOpacity: Double = 1.0
    
    init(transcript: String, isRecording: Bool) {
        self.transcript = transcript
        self.isRecording = isRecording
    }
}

