import SwiftUI

struct FollowersFollowingListView: View {
    let userId: String
    let mode: Mode // .followers or .following
    @Environment(\.dismiss) private var dismiss
    @State private var users: [UserSummary] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var nextCursor: String?
    @State private var hasMore = true
    
    enum Mode {
        case followers
        case following
        case mutuals
    }
    
    private let social = SupabaseSocialGraphService.shared
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            Task {
                                await loadUsers()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if users.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: mode == .followers ? "person.2" : (mode == .following ? "person.2.fill" : "person.3"))
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.6))
                        Text(emptyStateTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(emptyStateMessage)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(users) { user in
                                NavigationLink {
                                    UserProfileDetailView(userId: UUID(uuidString: user.id) ?? UUID())
                                } label: {
                                    UserCardView(user: user)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            if isLoadingMore {
                                ProgressView()
                                    .tint(.white)
                                    .padding()
                            } else if hasMore {
                                Button("Load More") {
                                    Task {
                                        await loadMore()
                                    }
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.white)
                                .padding()
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await loadUsers()
            }
        }
    }
    
    private var navigationTitle: String {
        switch mode {
        case .followers:
            return "Followers"
        case .following:
            return "Following"
        case .mutuals:
            return "Mutuals"
        }
    }
    
    private var emptyStateTitle: String {
        switch mode {
        case .followers:
            return "No followers yet"
        case .following:
            return "Not following anyone"
        case .mutuals:
            return "No mutual follows"
        }
    }
    
    private var emptyStateMessage: String {
        switch mode {
        case .followers:
            return "When someone follows you, they'll appear here"
        case .following:
            return "Start following users to see them here"
        case .mutuals:
            return "Users you both follow will appear here"
        }
    }
    
    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        nextCursor = nil
        hasMore = true
        defer { isLoading = false }
        
        do {
            switch mode {
            case .followers:
                let result = try await social.getFollowers(of: userId, cursor: nil, limit: 100)
                users = result.users
                nextCursor = result.nextCursor
                hasMore = result.hasMore
            case .following:
                let result = try await social.getFollowing(of: userId, cursor: nil, limit: 100)
                users = result.users
                nextCursor = result.nextCursor
                hasMore = result.hasMore
            case .mutuals:
                users = try await social.getMutuals(with: userId)
                hasMore = false
            }
        } catch {
            errorMessage = error.localizedDescription
            print("Error loading users: \(error)")
        }
    }
    
    private func loadMore() async {
        guard !isLoadingMore && hasMore, let cursor = nextCursor else { return }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            switch mode {
            case .followers:
                let result = try await social.getFollowers(of: userId, cursor: cursor, limit: 100)
                users.append(contentsOf: result.users)
                nextCursor = result.nextCursor
                hasMore = result.hasMore
            case .following:
                let result = try await social.getFollowing(of: userId, cursor: cursor, limit: 100)
                users.append(contentsOf: result.users)
                nextCursor = result.nextCursor
                hasMore = result.hasMore
            case .mutuals:
                // Mutuals doesn't support pagination yet
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            print("Error loading more users: \(error)")
        }
    }
}
