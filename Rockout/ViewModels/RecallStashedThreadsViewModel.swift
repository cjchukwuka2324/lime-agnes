import Foundation
import SwiftUI
import Combine

@MainActor
final class RecallStashedThreadsViewModel: ObservableObject {
    @Published var threads: [RecallThread] = []
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let threadStore = RecallThreadStore.shared
    private let recallService = RecallService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Observe search text changes
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] searchText in
                Task { @MainActor [weak self] in
                    await self?.loadThreads()
                }
            }
            .store(in: &cancellables)
    }
    
    func loadThreads() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            if searchText.isEmpty {
                threads = try await threadStore.fetchStashedThreads()
            } else {
                threads = try await threadStore.searchThreads(query: searchText)
            }
        } catch {
            errorMessage = error.localizedDescription
            Logger.recall.error("Failed to load threads: \(error.localizedDescription)")
        }
    }
    
    func deleteThread(_ thread: RecallThread) async {
        do {
            try await threadStore.deleteThread(threadId: thread.id)
            await loadThreads()
        } catch {
            errorMessage = error.localizedDescription
            Logger.recall.error("Failed to delete thread: \(error.localizedDescription)")
        }
    }
    
    func loadThreadMessages(threadId: UUID) async throws -> [RecallMessage] {
        let (messages, _, _) = try await recallService.fetchMessages(threadId: threadId, cursor: nil, limit: 100)
        return messages
    }
}






