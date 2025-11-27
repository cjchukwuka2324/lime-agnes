import SwiftUI

struct AcceptSharedAlbumView: View {
    let shareToken: String
    let onAccept: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isAccepting = false
    @State private var errorMessage: String?
    
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
    }
    
    private func acceptAlbum() {
        isAccepting = true
        errorMessage = nil
        
        Task {
            do {
                // Use ShareService directly to accept the album
                let shareService = ShareService.shared
                _ = try await shareService.acceptSharedAlbum(shareToken: shareToken)
                
                // Wait a moment for database to update
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                await MainActor.run {
                    isAccepting = false
                    onAccept() // This will trigger loadSharedAlbums() in parent view
                    dismiss()
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

