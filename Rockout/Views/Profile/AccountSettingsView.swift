import SwiftUI

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var spotifyAuth = SpotifyAuthService.shared
    private let profileService = UserProfileService.shared
    
    @State private var isLoading = false
    @State private var message: String?
    @State private var userProfile: UserProfileService.UserProfile?
    @State private var isLoadingProfile = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Solid black background
                Color.black
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Account Section
                        accountSection
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // Spotify Connection Section
                        SpotifyConnectionView()
                            .environmentObject(spotifyAuth)
                            .padding(.horizontal, 20)
                        
                        // Account Actions Section
                        accountActionsSection
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Settings")
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
            .task {
                await loadUserProfile()
            }
            .onAppear {
                // Reload profile when view appears (e.g., after returning from EditNameView)
                Task {
                    await loadUserProfile()
                }
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
                
                HStack {
                    Text("Name")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(displayName)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                HStack {
                    Text("Username")
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Text(displayUsername)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.white.opacity(0.05))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                NavigationLink {
                    EditNameView()
                } label: {
                    HStack {
                        Text("Change Name")
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                NavigationLink {
                    EditUsernameView()
                } label: {
                    HStack {
                        Text(userProfile?.username == nil ? "Set Username" : "Change Username")
                            .foregroundColor(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                }
                
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
            .glassMorphism()
        }
    }
    
    // MARK: - Account Actions Section
    
    private var accountActionsSection: some View {
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
    
    // MARK: - Computed Properties
    
    private var displayName: String {
        guard let profile = userProfile else {
            return "Not set"
        }
        
        if let firstName = profile.firstName, let lastName = profile.lastName,
           !firstName.isEmpty, !lastName.isEmpty {
            return "\(firstName) \(lastName)"
        } else if let displayName = profile.displayName, !displayName.isEmpty {
            return displayName
        } else {
            return "Not set"
        }
    }
    
    private var displayUsername: String {
        guard let profile = userProfile else {
            return "Not set"
        }
        
        if let username = profile.username, !username.isEmpty {
            return "@\(username)"
        } else {
            return "Not set"
        }
    }
    
    // MARK: - Functions
    
    private func loadUserProfile() async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        
        do {
            userProfile = try await profileService.getCurrentUserProfile()
        } catch {
            print("Failed to load user profile: \(error)")
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

