import Foundation
import SwiftUI
import Combine

@MainActor
final class UserSearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var results: [UserSummary] = []
    @Published var suggested: [UserSummary] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMoreResults = true
    @Published var errorMessage: String?
    
    private let social: SocialGraphService
    private let contactsService: ContactsService
    private let suggestedFollowService: SuggestedFollowService
    private var searchCancellable: AnyCancellable?
    private var currentOffset = 0
    private let pageSize = 20
    
    init(
        social: SocialGraphService = SupabaseSocialGraphService.shared,
        contactsService: ContactsService = SystemContactsService(),
        suggestedFollowService: SuggestedFollowService = SupabaseSuggestedFollowService()
    ) {
        self.social = social
        self.contactsService = contactsService
        self.suggestedFollowService = suggestedFollowService
        setupSearchDebounce()
    }
    
    private func setupSearchDebounce() {
        searchCancellable = $query
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] searchText in
                guard let self = self else { return }
                Task {
                    await self.search()
                }
            }
    }
    
    func search() async {
        isLoading = true
        errorMessage = nil
        currentOffset = 0
        hasMoreResults = true
        defer { isLoading = false }
        
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            results = []
            return
        }
        
        do {
            let result = try await social.searchUsersPaginated(
                query: query,
                limit: pageSize,
                offset: 0
            )
            results = result.users
            hasMoreResults = result.hasMore
            currentOffset = pageSize
            
            print("✅ Search returned \(result.users.count) users, hasMore: \(result.hasMore)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Search error: \(error.localizedDescription)")
            // Fallback to non-paginated search
            results = await social.searchUsers(query: query)
        }
    }
    
    func loadMore() async {
        guard !isLoadingMore, hasMoreResults else {
            print("⚠️ Skipping loadMore: isLoadingMore=\(isLoadingMore), hasMore=\(hasMoreResults)")
            return
        }
        
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            let result = try await social.searchUsersPaginated(
                query: query,
                limit: pageSize,
                offset: currentOffset
            )
            
            results.append(contentsOf: result.users)
            hasMoreResults = result.hasMore
            currentOffset += pageSize
            
            print("✅ Loaded \(result.users.count) more users, total: \(results.count)")
        } catch {
            print("❌ Error loading more users: \(error.localizedDescription)")
        }
    }
    
    func toggleFollow(_ user: UserSummary) async {
        do {
            if user.isFollowing {
                try await social.unfollow(userId: user.id)
            } else {
                try await social.follow(userId: user.id)
            }
            // Refresh search to update follow status
            await search()
            // Also refresh suggested
            await loadSuggested()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func loadSuggested() async {
        do {
            suggested = try await suggestedFollowService.loadSuggestions(contactService: contactsService)
        } catch {
            // If user denies contacts or suggestions fail, just leave empty
            print("Failed to load suggested follows: \(error.localizedDescription)")
            suggested = []
        }
    }
}
