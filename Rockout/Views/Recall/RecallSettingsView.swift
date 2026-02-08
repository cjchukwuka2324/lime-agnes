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
                    Section(header: Text("Voice"), footer: Text("When auto voice response is on, Recall speaks answers automatically and keeps listening for follow-up until you tap the orb to end the session.")) {
                        Toggle("Auto voice response", isOn: $autoSpeakResponses)
                            .accessibilityLabel("Auto voice response")
                            .accessibilityHint("When on, Recall speaks responses automatically. When off, tap the play button on a message to hear it.")
                        
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

