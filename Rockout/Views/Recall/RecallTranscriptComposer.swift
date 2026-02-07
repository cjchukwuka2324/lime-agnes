import SwiftUI

struct RecallTranscriptComposer: View {
    @Binding var rawTranscript: String
    @Binding var editedTranscript: String?
    let isVisible: Bool
    let onRetry: () -> Void
    let onAppend: () -> Void
    let onSend: (String) -> Void
    
    @State private var currentText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit Transcript")
                    .font(.headline)
                    .foregroundColor(.white)
                    .accessibilityAddTraits(.isHeader)
                
                TextField("Edit your transcript", text: $currentText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                    )
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .lineLimit(3...6)
                    .accessibilityLabel("Transcript editor")
                    .accessibilityHint("Edit your transcribed voice input before sending")
                    .accessibilityValue(currentText)
                
                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        Label("Retry", systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                    .accessibilityLabel("Retry recording")
                    .accessibilityHint("Double tap to discard this transcript and record again")
                    
                    Button(action: {
                        onAppend()
                    }) {
                        Label("Append", systemImage: "plus.circle")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.2))
                            )
                    }
                    .accessibilityLabel("Append recording")
                    .accessibilityHint("Double tap to continue recording and merge with this transcript")
                    
                    Spacer()
                    
                    Button(action: {
                        let finalText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !finalText.isEmpty {
                            onSend(finalText)
                        }
                    }) {
                        Label("Send", systemImage: "paperplane.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: "#1ED760"))
                            )
                    }
                    .accessibilityLabel("Send transcript")
                    .accessibilityHint("Double tap to send your edited transcript")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
            )
            .onAppear {
                currentText = editedTranscript ?? rawTranscript
                isFocused = true
            }
            .onChange(of: rawTranscript) { _, newValue in
                if editedTranscript == nil {
                    currentText = newValue
                }
            }
        }
    }
}

