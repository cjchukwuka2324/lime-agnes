import SwiftUI

struct RecallSourcesSheet: View {
    let sources: [RecallSource]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if sources.isEmpty {
                    VStack {
                        Text("No sources available")
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    List {
                        ForEach(sources) { source in
                            SourceRow(source: source)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Sources")
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

private struct SourceRow: View {
    let source: RecallSource
    
    var body: some View {
        Button {
            if let url = URL(string: source.url) {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(source.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let snippet = source.snippet {
                    Text(snippet)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }
                
                Text(source.url)
                    .font(.caption2)
                    .foregroundColor(Color(hex: "#1ED760"))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}








