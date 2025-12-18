import SwiftUI

struct RecallTextInputView: View {
    let onRecallCreated: (UUID) -> Void
    
    @State private var text: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    private let service = RecallService.shared
    
    var body: some View {
        VStack(spacing: 16) {
            TextField("Describe the song you're looking for...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.15))
                )
                .foregroundColor(.white)
                .tint(Color(hex: "#1ED760"))
                .lineLimit(3...8)
                .disabled(isCreating)
            
            Button {
                Task {
                    await createRecall()
                }
            } label: {
                if isCreating {
                    ProgressView()
                        .tint(.white)
                } else {
                    HStack {
                        Image(systemName: "sparkles.magnifyingglass")
                        Text("Find Song")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canCreate ? Color(hex: "#1ED760") : Color.gray.opacity(0.3))
                    )
                }
            }
            .disabled(!canCreate || isCreating)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
    }
    
    private var canCreate: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func createRecall() async {
        guard canCreate else { return }
        
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        
        do {
            let recallId = try await service.createRecall(
                inputType: .text,
                rawText: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            // Start processing
            try await service.processRecall(recallId: recallId)
            
            onRecallCreated(recallId)
        } catch {
            errorMessage = "Failed to create recall: \(error.localizedDescription)"
            print("❌ RecallTextInputView.createRecall error: \(error)")
        }
    }
}

