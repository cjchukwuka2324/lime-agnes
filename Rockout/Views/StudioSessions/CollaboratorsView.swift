import SwiftUI

struct CollaboratorsView: View {
    let albumId: UUID
    
    @Environment(\.dismiss) private var dismiss
    @State private var collaborators: [CollaboratorService.Collaborator] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedFilter: FilterType = .all
    @State private var userToRevoke: UUID?
    @State private var showRevokeConfirmation = false
    @State private var isRevoking = false
    
    enum FilterType {
        case all
        case collaborators
        case viewOnly
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading collaborators...")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.subheadline)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)
                        
                        Text("Error")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        
                        Button("Dismiss") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(12)
                    }
                } else if collaborators.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text("No Collaborators")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        Text("This album hasn't been shared with anyone yet.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    // Summary + list
                    let collaboratorCount = collaborators.filter { $0.is_collaboration }.count
                    let viewOnlyCount = collaborators.filter { !$0.is_collaboration }.count
                    
                    // Filter collaborators based on selected filter
                    let filteredCollaborators: [CollaboratorService.Collaborator] = {
                        switch selectedFilter {
                        case .all:
                            return collaborators
                        case .collaborators:
                            return collaborators.filter { $0.is_collaboration }
                        case .viewOnly:
                            return collaborators.filter { !$0.is_collaboration }
                        }
                    }()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        if collaboratorCount > 0 || viewOnlyCount > 0 {
                            HStack(spacing: 8) {
                                if collaboratorCount > 0 {
                                    Button {
                                        withAnimation {
                                            selectedFilter = selectedFilter == .collaborators ? .all : .collaborators
                                        }
                                    } label: {
                                        Label {
                                            Text("\(collaboratorCount) collaborator\(collaboratorCount == 1 ? "" : "s")")
                                        } icon: {
                                            Image(systemName: "person.2.fill")
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedFilter == .collaborators 
                                                   ? Color.blue.opacity(0.4) 
                                                   : Color.white.opacity(0.08))
                                        .foregroundColor(selectedFilter == .collaborators 
                                                        ? .blue 
                                                        : .white.opacity(0.8))
                                        .cornerRadius(999)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                if viewOnlyCount > 0 {
                                    Button {
                                        withAnimation {
                                            selectedFilter = selectedFilter == .viewOnly ? .all : .viewOnly
                                        }
                                    } label: {
                                        Label {
                                            Text("\(viewOnlyCount) view-only")
                                        } icon: {
                                            Image(systemName: "eye.fill")
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedFilter == .viewOnly 
                                                   ? Color.blue.opacity(0.4) 
                                                   : Color.white.opacity(0.08))
                                        .foregroundColor(selectedFilter == .viewOnly 
                                                        ? .blue 
                                                        : .white.opacity(0.8))
                                        .cornerRadius(999)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        }
                        
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if filteredCollaborators.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: selectedFilter == .collaborators ? "person.2.slash" : "eye.slash")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.5))
                                        
                                        Text(selectedFilter == .collaborators 
                                             ? "No Collaborators" 
                                             : "No View-Only Users")
                                            .font(.headline)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                } else {
                                    ForEach(filteredCollaborators) { collaborator in
                                        CollaboratorRow(
                                            collaborator: collaborator,
                                            onRevoke: {
                                                userToRevoke = collaborator.user_id
                                                showRevokeConfirmation = true
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                    }
                }
            }
            .navigationTitle("Collaborators")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                await loadCollaborators()
            }
            .alert("Revoke Access?", isPresented: $showRevokeConfirmation) {
                Button("Cancel", role: .cancel) {
                    userToRevoke = nil
                }
                Button("Revoke", role: .destructive) {
                    if let userId = userToRevoke {
                        Task {
                            await revokeAccess(for: userId)
                        }
                    }
                }
            } message: {
                if let userId = userToRevoke,
                   let collaborator = collaborators.first(where: { $0.user_id == userId }) {
                    Text("This will immediately revoke access for \(collaborator.display_name ?? collaborator.username ?? "this user"). They will no longer be able to view or collaborate on this album.")
                } else {
                    Text("This will immediately revoke access for this user. They will no longer be able to view or collaborate on this album.")
                }
            }
        }
    }
    
    private func loadCollaborators() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await CollaboratorService.shared.fetchCollaborators(for: albumId)
            await MainActor.run {
                collaborators = result
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
    
    private func revokeAccess(for userId: UUID) async {
        isRevoking = true
        errorMessage = nil
        
        do {
            try await ShareService.shared.revokeAccessForUser(albumId: albumId, userIdToRevoke: userId)
            
            // Remove from local list immediately
            await MainActor.run {
                collaborators.removeAll { $0.user_id == userId }
                userToRevoke = nil
            }
            
            // Reload to ensure we have the latest state
            await loadCollaborators()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                userToRevoke = nil
            }
        }
        
        isRevoking = false
    }
}

struct CollaboratorRow: View {
    let collaborator: CollaboratorService.Collaborator
    let onRevoke: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let imageURL = collaborator.profilePictureURL {
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
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
            )
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(collaborator.display_name ?? collaborator.username ?? collaborator.email ?? "Unknown User")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let username = collaborator.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                HStack(spacing: 8) {
                    if collaborator.is_collaboration {
                        Label("Collaborator", systemImage: "person.2.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(999)
                    } else {
                        Label("View Only", systemImage: "eye.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(999)
                    }
                }
            }
            
            Spacer()
            
            // Revoke Button
            Button {
                onRevoke()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            if let displayName = collaborator.display_name, !displayName.isEmpty {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundColor(.white)
            } else if let username = collaborator.username, !username.isEmpty {
                Text(String(username.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundColor(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
    }
}

