import SwiftUI

struct RecallStashedView: View {
    @StateObject private var viewModel = RecallViewModel()
    @State private var stashItems: [RecallStashItem] = []
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if stashItems.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.5))
                        Text("No stashed songs yet")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.7))
                        Text("Your searched songs will appear here")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                } else {
                    List {
                        ForEach(stashItems) { item in
                            StashRow(item: item) {
                                // Open thread
                                Task {
                                    await viewModel.openThread(threadId: item.threadId)
                                    dismiss()
                                }
                            }
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task {
                                        try? await RecallService.shared.deleteFromStash(threadId: item.threadId)
                                        await loadStash()
                                    }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Stashed")
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
            .onAppear {
                Task {
                    await loadStash()
                }
            }
        }
    }
    
    private func loadStash() async {
        isLoading = true
        defer { isLoading = false }
        stashItems = await viewModel.loadStash()
    }
}

private struct StashRow: View {
    let item: RecallStashItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundColor(Color(hex: "#1ED760"))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color(hex: "#1ED760").opacity(0.2))
                    )
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    if let title = item.topSongTitle, let artist = item.topSongArtist {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(artist)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    } else {
                        Text("Unknown song")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    HStack(spacing: 8) {
                        if let confidence = item.topConfidence {
                            Text("\(Int(confidence * 100))% confidence")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Text("•")
                            .foregroundColor(.white.opacity(0.4))
                        
                        Text(item.createdAt.timeAgo())
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }
}





