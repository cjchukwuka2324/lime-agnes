import SwiftUI

struct ShareSheetView: View {
    let resourceType: String // "album" or "track"
    let resourceId: UUID
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var shareToken: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var shareURL: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    Section {
                        ProgressView("Creating share link...")
                    }
                } else if let token = shareToken {
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
                    
                    Section("Link Info") {
                        HStack {
                            Text("Share Token")
                            Spacer()
                            Text(token.prefix(8))
                                .font(.caption)
                                .foregroundColor(.secondary)
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
            .task {
                await loadShareLink()
            }
        }
    }
    
    private func createShareLink() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // ShareService.createShareLink only works for albums currently
            guard resourceType == "album" else {
                errorMessage = "Sharing is only available for albums"
                isLoading = false
                return
            }
            
            let token = try await ShareService.shared.createShareLink(for: resourceId)
            shareToken = token
            shareURL = ShareService.shared.getShareURL(for: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func loadShareLink() async {
        // ShareService doesn't have getShareLink method, so we'll just create a new one
        await createShareLink()
    }
    
}

