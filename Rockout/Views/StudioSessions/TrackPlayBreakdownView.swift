import SwiftUI

struct TrackPlayBreakdownView: View {
    let track: StudioTrackRecord
    let album: StudioAlbumRecord
    
    @State private var userPlayCounts: [TrackPlayService.UserPlayCount] = []
    @State private var collaborators: [CollaboratorService.Collaborator] = []
    @State private var currentUserId: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isSearchActive = false
    
    @Environment(\.dismiss) private var dismiss
    
    private let trackPlayService = TrackPlayService.shared
    private let collaboratorService = CollaboratorService.shared
    
    // Filtered play counts based on search
    private var filteredUserPlayCounts: [TrackPlayService.UserPlayCount] {
        if searchText.isEmpty {
            return userPlayCounts
        }
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        // Remove @ if present for username comparison
        let queryWithoutAt = query.hasPrefix("@") ? String(query.dropFirst()) : query
        
        return userPlayCounts.filter { userPlayCount in
            let displayName = userPlayCount.profile.displayNameOrUsername.lowercased()
            let handle = userPlayCount.profile.handle.lowercased()
            let username = userPlayCount.profile.username?.lowercased() ?? ""
            
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
                        Text("Loading play data...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        
                        Text("Error Loading Plays")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Button {
                            Task {
                                await loadPlayCounts()
                            }
                        } label: {
                            Text("Retry")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: 200)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding(24)
                } else if userPlayCounts.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("No Plays Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("This track hasn't been played yet. Plays will appear here once users listen to the track.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        }
                        .padding(.top, 60)
                    } else {
                        ScrollView {
                            VStack(spacing: 16) {
                                // Track info header
                                VStack(spacing: 8) {
                                    Text(track.title)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                    
                                    if let duration = track.duration, duration > 0 {
                                        Text(formatTime(duration))
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                    
                                    Text("\(totalPlays) total play\(totalPlays == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.top, 4)
                                }
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(16)
                                
                                // Users list
                                if filteredUserPlayCounts.isEmpty && !searchText.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text("No users found")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding(.vertical, 40)
                                } else {
                                    VStack(spacing: 12) {
                                        ForEach(filteredUserPlayCounts) { userPlayCount in
                                            UserPlayCountRow(
                                                userPlayCount: userPlayCount,
                                                role: getUserRole(for: userPlayCount.userId)
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
            }
            .navigationTitle("Play Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Search icon (only show when search is not active)
                    if !isSearchActive {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isSearchActive = true
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white)
                                .font(.system(size: 18, weight: .medium))
                        }
                    }
                    
                    // Done button
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                await loadPlayCounts()
            }
        }
    }
    
    private var totalPlays: Int {
        userPlayCounts.reduce(0) { $0 + $1.playCount }
    }
    
    private var displayedPlays: Int {
        filteredUserPlayCounts.reduce(0) { $0 + $1.playCount }
    }
    
    private func loadPlayCounts() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Get current user ID first
            let supabase = SupabaseService.shared.client
            let currentUserIdValue = try await supabase.auth.session.user.id
            await MainActor.run {
                currentUserId = currentUserIdValue
            }
            
            // Load play counts and collaborators in parallel
            async let countsTask = trackPlayService.getPlayCountsPerUser(for: track.id)
            async let collaboratorsTask = collaboratorService.fetchCollaborators(for: album.id)
            
            let (counts, fetchedCollaborators) = try await (countsTask, collaboratorsTask)
            
            // Check if current user is a collaborator (since fetchCollaborators excludes current user)
            let currentUserStatus = try await checkCurrentUserCollaboratorStatus(albumId: album.id, userId: currentUserIdValue)
            
            await MainActor.run {
                userPlayCounts = counts
                collaborators = fetchedCollaborators
                currentUserCollaboratorStatus = currentUserStatus
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func checkCurrentUserCollaboratorStatus(albumId: UUID, userId: UUID) async throws -> (isCollaborator: Bool, isViewer: Bool) {
        let supabase = SupabaseService.shared.client
        
        struct SharedAlbumRecord: Codable {
            let is_collaboration: Bool
        }
        
        let response = try await supabase
            .from("shared_albums")
            .select("is_collaboration")
            .eq("album_id", value: albumId.uuidString)
            .eq("shared_with", value: userId.uuidString)
            .limit(1)
            .execute()
        
        let records = try JSONDecoder().decode([SharedAlbumRecord].self, from: response.data)
        
        if let record = records.first {
            return (isCollaborator: record.is_collaboration, isViewer: !record.is_collaboration)
        }
        
        return (isCollaborator: false, isViewer: false)
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct UserPlayCountRow: View {
    let userPlayCount: TrackPlayService.UserPlayCount
    let role: TrackPlayBreakdownView.UserRole
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile picture
            Group {
                if let imageURL = userPlayCount.profile.profilePictureURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(.white)
                        case .success(let image):
                            image.resizable().scaledToFill()
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
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(userPlayCount.profile.displayNameOrUsername)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // Role badge
                    roleBadge
                }
                
                if !userPlayCount.profile.handle.isEmpty {
                    Text(userPlayCount.profile.handle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Play count
            HStack(spacing: 6) {
                Image(systemName: "play.circle.fill")
                    .font(.caption)
                Text("\(userPlayCount.playCount)")
                    .font(.headline)
                Text("play\(userPlayCount.playCount == 1 ? "" : "s")")
                    .font(.subheadline)
            }
            .foregroundColor(.white.opacity(0.8))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var defaultAvatar: some View {
        Circle()
            .fill(LinearGradient(
                colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay(
                Text(String(userPlayCount.profile.displayNameOrUsername.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundColor(.white)
            )
    }
    
    @ViewBuilder
    private var roleBadge: some View {
        switch role {
        case .owner:
            HStack(spacing: 3) {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                Text("Owner")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.yellow)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.yellow.opacity(0.2))
            .cornerRadius(6)
            
        case .collaborator:
            HStack(spacing: 3) {
                Image(systemName: "person.2.fill")
                    .font(.caption2)
                Text("Collaborator")
                    .font(.caption2)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(6)
            
        case .viewer:
            EmptyView()
        }
    }
}

