import SwiftUI

struct GreenRoomPromptSheet: View {
    let promptText: String
    let onPost: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color(hex: "#1ED760"))
                    
                    Text("Ask GreenRoom?")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("We couldn't find a match after 2 attempts. Would you like to ask the GreenRoom community for help?")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your prompt:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Text("\"\(promptText)\"")
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.1))
                            )
                    }
                    .padding(.horizontal, 20)
                    
                    HStack(spacing: 16) {
                        Button {
                            onCancel()
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                        
                        Button {
                            onPost()
                            dismiss()
                        } label: {
                            Text("Post to GreenRoom")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(hex: "#1ED760"))
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 40)
            }
            .navigationTitle("Ask GreenRoom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}


















