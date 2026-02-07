import SwiftUI

struct RecallSettingsView: View {
    @AppStorage("recall.autoSpeakResponses") private var autoSpeakResponses: Bool = true
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color(hex: "#1A1A1A"),
                        Color(hex: "#0A0A0A"),
                        Color(hex: "#1A1A1A")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                Form {
                    Section(header: Text("Audio Settings")) {
                        Toggle("Auto-speak responses", isOn: $autoSpeakResponses)
                            .accessibilityLabel("Auto-speak responses")
                            .accessibilityHint("When enabled, assistant responses will automatically play audio. When disabled, you must tap the play button to hear responses.")
                        
                        if reduceMotion {
                            Text("Reduced motion is enabled. Audio playback may be limited.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.1))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Recall Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
}

