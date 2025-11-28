import SwiftUI

struct ShareSheetView: View {
    let resourceType: String // "album" or "track"
    let resourceId: UUID
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var shareToken: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var shareURL: String = ""
    @State private var isCollaboration: Bool = false
    @State private var showShareSheet = false
    @State private var copiedToClipboard = false
    
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
            // Don't auto-create link, let user choose collaboration setting first
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
            
            Text("Share this album with others. Choose whether they can view or collaborate.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Collaboration Toggle
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
        }
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
            
            let token = try await ShareService.shared.createShareLink(for: resourceId, isCollaboration: isCollaboration)
            shareToken = token
            shareURL = ShareService.shared.getShareURL(for: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
