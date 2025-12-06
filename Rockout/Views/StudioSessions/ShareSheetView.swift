import SwiftUI

struct ShareSheetView: View {
    let resourceType: String // "album" or "track"
    let resourceId: UUID
    let allowCollaboration: Bool // Whether collaboration mode is allowed (false for view-only shares)
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var shareToken: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var shareURL: String = ""
    @State private var isCollaboration: Bool = false
    @State private var showShareSheet = false
    @State private var copiedToClipboard = false
    @State private var hasExpiration: Bool = false
    @State private var expirationDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var shareLinkDetails: ShareableLink?
    @State private var showRevokeConfirmation = false
    @State private var isRevoking = false
    @State private var usersWithAccess: [CollaboratorService.Collaborator] = []
    @State private var isLoadingAccess = false
    @State private var showManageAccess = false
    @State private var userToRevoke: UUID?
    @State private var showRevokeUserConfirmation = false
    
    init(resourceType: String, resourceId: UUID, allowCollaboration: Bool = true) {
        self.resourceType = resourceType
        self.resourceId = resourceId
        self.allowCollaboration = allowCollaboration
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        loadingView
                    } else if let token = shareToken {
                        shareLinkView(token: token)
                    } else {
                        createLinkView
                    }
                    
                    if let error = errorMessage {
                        errorView(error)
                    }
                }
                .padding(20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Share Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            // Ensure navigation bar is always opaque
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .black
            appearance.shadowColor = .clear
            
            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
            UINavigationBar.appearance().compactAppearance = appearance
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [shareURL])
        }
        .task {
            // Load existing share link if one exists
            await loadExistingShareLink()
        }
    }
    
    // MARK: - Create Link View
    private var createLinkView: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "link")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.top, 20)
            
            Text("Create Share Link")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(allowCollaboration 
                 ? "Share this album with others. Choose whether they can view or collaborate."
                 : "Share this album with others. Recipients will have view-only access.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Collaboration Toggle (only shown if collaboration is allowed)
            if allowCollaboration {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: isCollaboration ? "person.2.fill" : "eye.fill")
                                    .font(.title3)
                                    .foregroundColor(isCollaboration ? .blue : .white.opacity(0.7))
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(isCollaboration ? "Collaboration" : "View Only")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text(isCollaboration 
                                         ? "Recipients can edit this album" 
                                         : "Recipients can only view this album")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $isCollaboration)
                            .tint(.blue)
                            .labelsHidden()
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .padding(.horizontal, 20)
            } else {
                // View-only mode indicator (no toggle)
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "eye.fill")
                                    .font(.title3)
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("View Only")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("Recipients can only view this album")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .padding(.horizontal, 20)
            }
            
            // Expiration Settings
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Link Expiration")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text(hasExpiration 
                                     ? "Link will expire on selected date" 
                                     : "Link will remain active indefinitely")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $hasExpiration)
                        .tint(.blue)
                        .labelsHidden()
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.1))
                )
                
                if hasExpiration {
                    DatePicker(
                        "Expiration Date",
                        selection: $expirationDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 20)
            
            // Create Button
            Button {
                Task {
                    await createShareLink()
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "link.badge.plus")
                            .font(.headline)
                    }
                    Text("Create Share Link")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }
            .padding(.horizontal, 20)
            .disabled(isLoading)
        }
    }
    
    // MARK: - Share Link View
    private func shareLinkView(token: String) -> some View {
        VStack(spacing: 24) {
            // Success Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.3), Color.blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(.green)
            }
            .padding(.top, 20)
            
            Text("Share Link Created")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Share Link Card
            VStack(spacing: 16) {
                HStack {
                    Text("Share Link")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                }
                
                // Link Display
                HStack(spacing: 12) {
                    Text(shareURL)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    
                    Spacer()
                    
                    Button {
                        UIPasteboard.general.string = shareURL
                        withAnimation {
                            copiedToClipboard = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                copiedToClipboard = false
                            }
                        }
                    } label: {
                        Image(systemName: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.title3)
                            .foregroundColor(copiedToClipboard ? .green : .blue)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                )
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        showShareSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.headline)
                            Text("Share via...")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    
                    Button {
                        UIPasteboard.general.string = shareURL
                        withAnimation {
                            copiedToClipboard = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                copiedToClipboard = false
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.headline)
                            Text(copiedToClipboard ? "Copied!" : "Copy Link")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.1))
            )
            .padding(.horizontal, 20)
            
            // Collaboration Badge
            if isCollaboration {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                    Text("Collaboration Mode")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.2))
                )
            }
            
            // Expiration Info
            if let details = shareLinkDetails, let expiresAt = details.expires_at {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                    Text("Expires: \(formatExpirationDate(expiresAt))")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.2))
                )
            } else if let details = shareLinkDetails, details.expires_at == nil {
                HStack(spacing: 8) {
                    Image(systemName: "infinity")
                        .font(.caption)
                    Text("Never expires")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.2))
                )
            }
            
            // Manage Access Section
            if let token = shareToken {
                manageAccessSection
            }
            
            // Revoke Entire Share Link Button
            if let token = shareToken {
                Button {
                    showRevokeConfirmation = true
                } label: {
                    HStack {
                        if isRevoking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.headline)
                            Text("Revoke Entire Share Link")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                .disabled(isRevoking)
            }
        }
        .alert("Revoke Share Link?", isPresented: $showRevokeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Revoke", role: .destructive) {
                Task {
                    await revokeShareLink()
                }
            }
        } message: {
            Text("This will immediately revoke access for everyone using this share link and remove all shared access. This action cannot be undone.")
        }
        .alert("Revoke Access for User?", isPresented: $showRevokeUserConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Revoke", role: .destructive) {
                if let userId = userToRevoke {
                    Task {
                        await revokeUserAccess(userId: userId)
                    }
                }
            }
        } message: {
            Text("This will immediately revoke access for this user. They will no longer be able to view or collaborate on this album.")
        }
    }
    
    // MARK: - Helper Functions
    private func formatExpirationDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
    
    private func revokeShareLink() async {
        guard let token = shareToken else { return }
        
        isRevoking = true
        errorMessage = nil
        
        do {
            try await ShareService.shared.revokeShareLink(shareToken: token)
            // Reset share link state
            await MainActor.run {
                shareToken = nil
                shareURL = ""
                shareLinkDetails = nil
                usersWithAccess = []
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        
        isRevoking = false
    }
    
    private func revokeUserAccess(userId: UUID) async {
        isLoadingAccess = true
        errorMessage = nil
        
        do {
            try await ShareService.shared.revokeAccessForUser(albumId: resourceId, userIdToRevoke: userId)
            // Reload users with access
            await loadUsersWithAccess()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
        
        isLoadingAccess = false
    }
    
    private func loadUsersWithAccess() async {
        isLoadingAccess = true
        
        do {
            let users = try await ShareService.shared.getAllUsersWithAccess(for: resourceId)
            await MainActor.run {
                usersWithAccess = users
            }
        } catch {
            print("⚠️ Failed to load users with access: \(error.localizedDescription)")
            await MainActor.run {
                usersWithAccess = []
            }
        }
        
        isLoadingAccess = false
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            
            Text("Creating share link...")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Manage Access Section
    private var manageAccessSection: some View {
        VStack(spacing: 16) {
            Button {
                showManageAccess.toggle()
                if showManageAccess {
                    Task {
                        await loadUsersWithAccess()
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.2.fill")
                        .font(.headline)
                    Text("Manage Access")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: showManageAccess ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            
            if showManageAccess {
                if isLoadingAccess {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                } else if usersWithAccess.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.5))
                        Text("No one has access yet")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(usersWithAccess) { user in
                                UserAccessRow(user: user) {
                                    userToRevoke = user.user_id
                                    showRevokeUserConfirmation = true
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .frame(maxHeight: 300)
                }
            }
        }
    }
    
    // MARK: - User Access Row
    private struct UserAccessRow: View {
        let user: CollaboratorService.Collaborator
        let onRevoke: () -> Void
        
        var body: some View {
            HStack(spacing: 12) {
                // Avatar
                Group {
                    if let imageURL = user.profilePictureURL {
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
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
                
                // User Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.display_name ?? user.username ?? user.email ?? "Unknown User")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if let username = user.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: user.is_collaboration ? "person.2.fill" : "eye.fill")
                            .font(.caption2)
                        Text(user.is_collaboration ? "Collaborator" : "View Only")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
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
            .padding(.vertical, 10)
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
                
                if let displayName = user.display_name, !displayName.isEmpty {
                    Text(String(displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.white)
                } else if let username = user.username, !username.isEmpty {
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
    
    // MARK: - Error View
    private func errorView(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.2))
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Functions
    private func createShareLink() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard resourceType == "album" else {
                errorMessage = "Sharing is only available for albums"
                isLoading = false
                return
            }
            
            // Force view-only if collaboration is not allowed
            let collaborationMode = allowCollaboration ? isCollaboration : false
            
            // Set expiration date if enabled
            let expiration = hasExpiration ? expirationDate : nil
            
            let token = try await ShareService.shared.createShareLink(for: resourceId, isCollaboration: collaborationMode, expiresAt: expiration)
            shareToken = token
            // Deep link format:
            //   - View-only:   rockout://view/{token}
            //   - Collaborate: rockout://collaborate/{token}
            shareURL = ShareService.shared.getShareURL(for: token, isCollaboration: collaborationMode)
            
            // Update isCollaboration state to match what was actually created
            isCollaboration = collaborationMode
            
            // Fetch share link details to show expiration
            shareLinkDetails = try await ShareService.shared.getShareLinkDetails(for: resourceId)
            
            // Load users with access
            await loadUsersWithAccess()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func loadExistingShareLink() async {
        do {
            if let existingLink = try await ShareService.shared.getShareLinkDetails(for: resourceId) {
                await MainActor.run {
                    shareToken = existingLink.share_token
                    isCollaboration = existingLink.is_collaboration ?? false
                    shareLinkDetails = existingLink
                    shareURL = ShareService.shared.getShareURL(for: existingLink.share_token, isCollaboration: isCollaboration)
                    
                    // Set expiration state if link has expiration
                    if let expiresAtString = existingLink.expires_at {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        if let expiresAt = formatter.date(from: expiresAtString) {
                            hasExpiration = true
                            expirationDate = expiresAt
                        }
                    }
                }
                
                // Load users with access
                await loadUsersWithAccess()
            }
        } catch {
            // No existing share link, that's fine
            print("ℹ️ No existing share link found: \(error.localizedDescription)")
        }
    }
}
