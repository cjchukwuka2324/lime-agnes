import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var spotifyAuth = SpotifyAuthService.shared

    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Account Section
                        accountSection
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // Spotify Connection Section
                        SpotifyConnectionView()
                            .environmentObject(spotifyAuth)
                        
                        // Logout Section
                        logoutSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await authVM.refreshUser()
                await spotifyAuth.loadConnection()
            }
        }
    }
    
    // MARK: - Account Section
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(spacing: 0) {
                HStack {
                    Text("Email")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(authVM.currentUserEmail ?? "Unknown")
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                NavigationLink {
                    ResetPasswordView()
                } label: {
                    HStack {
                        Text("Change Password")
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                }
            }
            .cornerRadius(12)
        }
    }
    
    // MARK: - Logout Section
    private var logoutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Account Actions")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                // Log out of Rockout
                Button(role: .destructive) {
                    logout()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Log Out of Rockout")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(12)
                }
                .disabled(isLoading)
                
                // Note about Spotify
                if spotifyAuth.isAuthorized() {
                    Text("Note: Logging out of Rockout will also disconnect Spotify")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }

    private func logout() {
        Task {
            isLoading = true
            defer { isLoading = false }
            
            // Always disconnect Spotify when logging out (clears local storage too)
            await spotifyAuth.disconnect()
            
            // Log out of Rockout
            await authVM.logout()
            message = "Logged out."
        }
    }
}
