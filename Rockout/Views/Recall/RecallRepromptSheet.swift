import SwiftUI

struct RecallRepromptSheet: View {
    let originalQuery: String
    let onReprompt: (String) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var repromptText = ""
    @State private var selectedInputType: RepromptInputType = .text
    
    init(originalQuery: String, onReprompt: @escaping (String) -> Void) {
        self.originalQuery = originalQuery
        self.onReprompt = onReprompt
        // Pre-populate with original query for editing
        _repromptText = State(initialValue: originalQuery)
    }
    
    enum RepromptInputType {
        case text
        case voice
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Original query context
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Refining search")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("Original: \"\(originalQuery)\"")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .italic()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    )
                    .padding(.horizontal, 20)
                    
                    // Input type selector
                    Picker("Input Type", selection: $selectedInputType) {
                        Text("Text").tag(RepromptInputType.text)
                        Text("Voice").tag(RepromptInputType.voice)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    
                    // Input area
                    if selectedInputType == .text {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Edit your query...", text: $repromptText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.1))
                                )
                                .foregroundColor(.white)
                                .lineLimit(3...8)
                                .accessibilityLabel("Edit query text field")
                                .accessibilityHint("Edit your search query to refine the search")
                            
                            // Edit original button
                            Button {
                                repromptText = originalQuery
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 12))
                                    Text("Reset to original")
                                        .font(.caption)
                                }
                                .foregroundColor(Color(hex: "#1ED760"))
                            }
                            .accessibilityLabel("Reset to original query")
                            .accessibilityHint("Double tap to restore the original search query")
                        }
                        .padding(.horizontal, 20)
                    } else {
                        // Voice input - use main orb
                        VStack(spacing: 16) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 48))
                                .foregroundColor(Color(hex: "#1ED760"))
                            
                            Text("Close this sheet and tap the orb to record voice")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.1))
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // Send button
                    if selectedInputType == .text {
                        Button {
                            if !repromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                onReprompt(repromptText)
                            }
                        } label: {
                            Text("Refine Search")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(canSend ? Color(hex: "#1ED760") : Color.white.opacity(0.2))
                                )
                        }
                        .disabled(!canSend)
                        .accessibilityLabel("Refine Search")
                        .accessibilityHint("Double tap to refine your search with the edited query")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Refine Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Double tap to cancel and close this sheet")
                }
            }
        }
    }
    
    private var canSend: Bool {
        selectedInputType == .voice || !repromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

