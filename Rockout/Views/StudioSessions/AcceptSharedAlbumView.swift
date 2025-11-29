import SwiftUI

struct AcceptSharedAlbumView: View {
    let shareToken: String
    let onAccept: (Bool) -> Void // Pass isCollaboration flag
    let onOwnerDetected: () -> Void // Callback when owner is detected
    
    @Environment(\.dismiss) private var dismiss
    @State private var isAccepting = false
    @State private var errorMessage: String?
    @State private var isOwner = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    if isAccepting {
                        ProgressView()
                            .tint(.white)
                            .padding()
                        
                        Text("Accepting shared album...")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.subheadline)
                    } else if errorMessage == "OWNER_MESSAGE" {
                        // Owner clicked their own share link
                        VStack(spacing: 20) {
                            Image(systemName: "person.crop.circle.fill.badge.checkmark")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            Text("You Own This Album")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("This is your album. You can find it in the \"My Albums\" tab.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            
                            Button {
                                onOwnerDetected()
                                dismiss()
                            } label: {
                                Text("Go to My Albums")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        }
                        .padding(.top, 40)
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
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white)
                            
                            Text("Shared Album")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("You've been invited to view a shared album")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            
                            Button {
                                acceptAlbum()
                            } label: {
                                Text("Accept & View")
                                    .font(.headline)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        }
                        .padding(.top, 40)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Shared Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .task {
            // Check if user is owner when view appears
            await checkIfOwner()
        }
    }
    
    private func checkIfOwner() async {
        do {
            let shareService = ShareService.shared
            // Try to accept - this will throw if user is owner
            _ = try await shareService.acceptSharedAlbum(shareToken: shareToken)
        } catch let error as NSError {
            if error.domain == "ShareService" && error.code == 403 {
                // User is the owner
                await MainActor.run {
                    isOwner = true
                    errorMessage = "OWNER_MESSAGE"
                }
            }
        } catch {
            // Other errors - ignore for now, will be handled when user tries to accept
        }
    }
    
    private func acceptAlbum() {
        isAccepting = true
        errorMessage = nil
        
        Task {
            do {
                // Use ShareService directly to accept the album
                let shareService = ShareService.shared
                let (album, isCollaboration) = try await shareService.acceptSharedAlbum(shareToken: shareToken)
                
                // Wait a moment for database to update
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                await MainActor.run {
                    isAccepting = false
                    onAccept(isCollaboration) // Pass collaboration flag to parent
                    dismiss()
                }
            } catch let error as NSError {
                await MainActor.run {
                    isAccepting = false
                    if error.domain == "ShareService" && error.code == 403 {
                        // User is the owner
                        errorMessage = "OWNER_MESSAGE"
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    print("❌ Error accepting shared album: \(error)")
                }
            } catch {
                await MainActor.run {
                    isAccepting = false
                    errorMessage = error.localizedDescription
                    print("❌ Error accepting shared album: \(error)")
                }
            }
        }
    }
}

