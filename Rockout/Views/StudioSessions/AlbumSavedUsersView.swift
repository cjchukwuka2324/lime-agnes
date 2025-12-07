import SwiftUI

struct AlbumSavedUsersView: View {
    let album: StudioAlbumRecord
    
    @State private var savedUsers: [AlbumService.SavedUserInfo] = []
    @State private var collaborators: [CollaboratorService.Collaborator] = []
    @State private var currentUserId: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isSearchActive = false
    
    @Environment(\.dismiss) private var dismiss
    
    private let albumService = AlbumService.shared
    private let collaboratorService = CollaboratorService.shared
    
    // Filtered saved users based on search
    private var filteredSavedUsers: [AlbumService.SavedUserInfo] {
        if searchText.isEmpty {
            return savedUsers
        }
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        // Remove @ if present for username comparison
        let queryWithoutAt = query.hasPrefix("@") ? String(query.dropFirst()) : query
        
        return savedUsers.filter { savedUser in
            let displayName = savedUser.displayNameOrUsername.lowercased()
            let handle = savedUser.handle.lowercased()
            let username = savedUser.username?.lowercased() ?? ""
            
            // Search by display name, handle, or username (with or without @)
            return displayName.contains(query) ||
                   handle.contains(query) ||
                   handle.contains(queryWithoutAt) ||
                   username.contains(queryWithoutAt)
        }
    }
    
    @State private var currentUserCollaboratorStatus: (isCollaborator: Bool, isViewer: Bool)?
    
    // Helper to determine user role
    private func getUserRole(for userId: UUID) -> UserRole {
        // Check if owner
        if userId == album.artist_id {
            return .owner
        }
        
        // Check if this is the current user - use stored status
        if let currentUserId = currentUserId, userId == currentUserId,
           let status = currentUserCollaboratorStatus {
            if status.isCollaborator {
                return .collaborator
            } else if status.isViewer {
                return .viewer
            }
        }
        
        // Check if collaborator in the list
        if collaborators.contains(where: { $0.user_id == userId && $0.is_collaboration }) {
            return .collaborator
        }
        // Check if view-only in the list
        if collaborators.contains(where: { $0.user_id == userId && !$0.is_collaboration }) {
            return .viewer
        }
        
        return .viewer
    }
    
    enum UserRole {
        case owner
        case collaborator
        case viewer
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom search bar (when active) - positioned below navigation bar
                    if isSearchActive {
                        HStack(spacing: 12) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.white.opacity(0.6))
                                
                                TextField("Search users...", text: $searchText)
                                    .foregroundColor(.white)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.15))
                            )
                            
                            // Cancel button next to search field
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isSearchActive = false
                                    searchText = ""
                                }
                            } label: {
                                Text("Cancel")
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // Main content
                    ZStack {
                        Color.black.ignoresSafeArea()
                        
                        if isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .tint(.white)
                                Text("Loading saved users...")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else if let error = errorMessage {
                            VStack(spacing: 20) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.orange)
                                
                                Text("Error Loading Users")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                
                                Button {
                                    Task {
                                        await loadSavedUsers()
                                    }
                                } label: {
                                    Text("Retry")
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                        .background(Color.blue)
                                        .cornerRadius(25)
                                }
                            }
                        } else if savedUsers.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "bookmark.slash")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.5))
                                
                                Text("No Saves Yet")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text("Users who save this album from Discover will appear here")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                        } else {
                            ScrollView {
                                VStack(spacing: 16) {
                                    // Album info header
                                    VStack(spacing: 8) {
                                        Text(album.title)
                                            .font(.title2.bold())
                                            .foregroundColor(.white)
                                        
                                        Text("\(savedUsers.count) user\(savedUsers.count == 1 ? "" : "s") saved")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding(.top, 20)
                                    .padding(.bottom, 8)
                                    
                                    // Users list
                                    if filteredSavedUsers.isEmpty && !searchText.isEmpty {
                                        VStack(spacing: 12) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 32))
                                                .foregroundColor(.white.opacity(0.5))
                                            Text("No users found")
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        .padding(.top, 40)
                                    } else {
                                        VStack(spacing: 12) {
                                            ForEach(filteredSavedUsers) { savedUser in
                                                SavedUserRow(
                                                    savedUser: savedUser,
                                                    role: getUserRole(for: savedUser.userId)
                                                )
                                            }
                                        }
                                        .padding(.bottom, 20)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                            }
                        }
                    }
                }
                .navigationTitle("Saved Users")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    if isSearchActive {
                                        isSearchActive = false
                                        searchText = ""
                                    } else {
                                        isSearchActive = true
                                    }
                                }
                            } label: {
                                Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                                    .foregroundColor(.white)
                                    .font(.system(size: 18, weight: .medium))
                            }
                            
                            Button("Done") {
                                dismiss()
                            }
                            .foregroundColor(.white)
                        }
                    }
                }
                .task {
                    await loadSavedUsers()
                }
            }
        }
    }
    
    private func loadSavedUsers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            // Get current user ID
            let session = try await SupabaseService.shared.client.auth.session
            currentUserId = session.user.id
            
            // Load saved users
            savedUsers = try await albumService.getUsersWhoSavedAlbum(albumId: album.id)
            
            // Load collaborators to determine roles
            do {
                collaborators = try await collaboratorService.fetchCollaborators(for: album.id)
                
                // Check current user's collaborator status
                if let currentUserId = currentUserId {
                    let isCollaborator = collaborators.contains(where: { $0.user_id == currentUserId && $0.is_collaboration })
                    let isViewer = collaborators.contains(where: { $0.user_id == currentUserId && !$0.is_collaboration })
                    currentUserCollaboratorStatus = (isCollaborator: isCollaborator, isViewer: isViewer)
                }
            } catch {
                print("⚠️ Could not load collaborators: \(error.localizedDescription)")
            }
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Error loading saved users: \(error.localizedDescription)")
        }
    }
}

struct SavedUserRow: View {
    let savedUser: AlbumService.SavedUserInfo
    let role: AlbumSavedUsersView.UserRole
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile Picture
            Group {
                if let imageURL = savedUser.profilePictureURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            defaultAvatar
                        @unknown default:
                            defaultAvatar
                        }
                    }
                } else {
                    defaultAvatar
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(savedUser.displayNameOrUsername)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    roleBadge
                }
                
                if !savedUser.handle.isEmpty {
                    Text(savedUser.handle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                HStack(spacing: 16) {
                    if savedUser.completedListen {
                        Label("Completed", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    if savedUser.replayCount > 0 {
                        Label("\(savedUser.replayCount) replay\(savedUser.replayCount == 1 ? "" : "s")", systemImage: "repeat")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    if let discoveredAt = savedUser.discoveredAt {
                        Text(timeAgo(from: discoveredAt))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var roleBadge: some View {
        Group {
            switch role {
            case .owner:
                Label("Owner", systemImage: "crown.fill")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.yellow.opacity(0.2))
                    .foregroundColor(.yellow)
                    .cornerRadius(999)
            case .collaborator:
                Label("Collaborator", systemImage: "person.2.fill")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(999)
            case .viewer:
                EmptyView() // No badge for regular viewers
            }
        }
    }
    
    private var defaultAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.2, green: 0.2, blue: 0.3),
                        Color(red: 0.1, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(savedUser.displayNameOrUsername.prefix(1).uppercased())
                    .font(.title3.bold())
                    .foregroundColor(.white)
            )
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

