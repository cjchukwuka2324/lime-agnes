import SwiftUI

struct RecallStashedThreadsView: View {
    @StateObject private var viewModel = RecallStashedThreadsViewModel()
    @ObservedObject var recallViewModel: RecallViewModel
    @Environment(\.dismiss) var dismiss
    @State private var lastMessageSnippets: [UUID: String] = [:]
    
    init(recallViewModel: RecallViewModel) {
        self.recallViewModel = recallViewModel
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else if viewModel.threads.isEmpty {
                    emptyStateView
                } else {
                    threadsListView
                }
            }
            .navigationTitle("Stashed Threads")
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
            .searchable(text: $viewModel.searchText, prompt: "Search threads")
            .onAppear {
                Task {
                    await viewModel.loadThreads()
                    await loadLastMessageSnippets()
                }
            }
            .onChange(of: viewModel.threads) { _, _ in
                Task {
                    await loadLastMessageSnippets()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.5))
                .accessibilityHidden(true)
            Text("No stashed threads yet")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
                .accessibilityLabel("No stashed threads yet")
            Text("Your conversation threads will appear here")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .accessibilityLabel("Your conversation threads will appear here")
        }
        .accessibilityElement(children: .combine)
    }
    
    private var threadsListView: some View {
        List {
            ForEach(viewModel.threads) { thread in
                ThreadRow(
                    thread: thread,
                    lastMessageSnippet: lastMessageSnippets[thread.id],
                    onTap: {
                        Task {
                            await openThread(thread)
                        }
                    }
                )
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteThread(thread)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    private func openThread(_ thread: RecallThread) async {
        do {
            // Load thread messages
            let messages = try await viewModel.loadThreadMessages(threadId: thread.id)
            
            // Update recall view model with thread and messages
            await recallViewModel.openThread(threadId: thread.id)
            
            // Dismiss this view
            dismiss()
        } catch {
            Logger.recall.error("Failed to open thread: \(error.localizedDescription)")
        }
    }
    
    private func loadLastMessageSnippets() async {
        let threadStore = RecallThreadStore.shared
        var snippets: [UUID: String] = [:]
        
        for thread in viewModel.threads {
            if let snippet = try? await threadStore.getLastMessageSnippet(threadId: thread.id) {
                snippets[thread.id] = snippet
            }
        }
        
        lastMessageSnippets = snippets
    }
}

private struct ThreadRow: View {
    let thread: RecallThread
    let lastMessageSnippet: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.title3)
                    .foregroundColor(Color(hex: "#1ED760"))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color(hex: "#1ED760").opacity(0.2))
                    )
                    .accessibilityHidden(true)
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.title ?? "New Recall")
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let snippet = lastMessageSnippet, !snippet.isEmpty {
                        Text(snippet)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(2)
                    } else {
                        Text("No messages yet")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 8) {
                        Text(thread.lastMessageAt.timeAgo())
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(thread.title ?? "New Recall"), \(lastMessageSnippet ?? "No messages yet"), \(thread.lastMessageAt.timeAgo())")
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .accessibilityHidden(true)
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

