import SwiftUI

struct ShareSheetView: View {
    let resourceType: String // "album" or "track"
    let resourceId: UUID
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var shareLink: ShareableLink?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var shareURL: String = ""
    @State private var showPasswordSheet = false
    @State private var password: String = ""
    @State private var listeners: [ListenerRecord] = []
    
    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section {
                        ProgressView("Creating share link...")
                    }
                } else if let link = shareLink {
                    Section("Share Link") {
                        HStack {
                            Text(shareURL)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = shareURL
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                        
                        Button {
                            let activityVC = UIActivityViewController(
                                activityItems: [shareURL],
                                applicationActivities: nil
                            )
                            
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootVC = windowScene.windows.first?.rootViewController {
                                rootVC.present(activityVC, animated: true)
                            }
                        } label: {
                            Label("Share via...", systemImage: "square.and.arrow.up")
                        }
                    }
                    
                    Section("Link Settings") {
                        HStack {
                            Text("Access Count")
                            Spacer()
                            Text("\(link.access_count)")
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            showPasswordSheet = true
                        } label: {
                            HStack {
                                Text("Password Protection")
                                Spacer()
                                if link.password != nil {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        
                        Button {
                            Task {
                                await revokeLink()
                            }
                        } label: {
                            Text("Revoke Link")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Section("Recent Listeners") {
                        if listeners.isEmpty {
                            Text("No listeners yet")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(listeners.prefix(5)) { listener in
                                HStack {
                                    Image(systemName: "person.circle")
                                    VStack(alignment: .leading) {
                                        Text(listener.listener_id != nil ? "User" : "Anonymous")
                                            .font(.caption)
                                        Text(formatDate(listener.listened_at))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if let duration = listener.duration_listened {
                                        Text(formatTime(duration))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Button {
                            Task {
                                await createShareLink()
                            }
                        } label: {
                            Text("Create Share Link")
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Share")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPasswordSheet) {
                PasswordProtectionSheet(
                    currentPassword: shareLink?.password,
                    onSave: { newPassword in
                        password = newPassword
                        Task {
                            await updatePassword(newPassword)
                        }
                    }
                )
            }
            .task {
                await loadShareLink()
                await loadListeners()
            }
        }
    }
    
    private func createShareLink() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let link = try await ShareService.shared.createShareLink(
                for: resourceType,
                resourceId: resourceId
            )
            shareLink = link
            shareURL = ShareService.shared.generateShareURL(for: link)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func loadShareLink() async {
        do {
            if let link = try await ShareService.shared.getShareLink(for: resourceType, resourceId: resourceId) {
                shareLink = link
                shareURL = ShareService.shared.generateShareURL(for: link)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func loadListeners() async {
        guard let link = shareLink else { return }
        do {
            listeners = try await ShareService.shared.getListeners(for: link.id)
        } catch {
            // Silently fail for listeners
        }
    }
    
    private func revokeLink() async {
        guard let link = shareLink else { return }
        do {
            try await ShareService.shared.revokeShareLink(link)
            shareLink = nil
            shareURL = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func updatePassword(_ newPassword: String) async {
        // This would require updating the ShareService to support password updates
        // For now, we'll recreate the link with password
        guard let link = shareLink else { return }
        
        do {
            try await ShareService.shared.revokeShareLink(link)
            let newLink = try await ShareService.shared.createShareLink(
                for: resourceType,
                resourceId: resourceId,
                password: newPassword.isEmpty ? nil : newPassword
            )
            shareLink = newLink
            shareURL = ShareService.shared.generateShareURL(for: newLink)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        displayFormatter.timeStyle = .short
        return displayFormatter.string(from: date)
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PasswordProtectionSheet: View {
    let currentPassword: String?
    let onSave: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirmPassword)
                } header: {
                    Text("Set Password")
                } footer: {
                    Text("Leave empty to remove password protection")
                }
            }
            .navigationTitle("Password Protection")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if password == confirmPassword {
                            onSave(password)
                            dismiss()
                        }
                    }
                    .disabled(password != confirmPassword && !password.isEmpty)
                }
            }
        }
    }
}

