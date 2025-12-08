import SwiftUI

struct EditUsernameView: View {
    @Environment(\.dismiss) private var dismiss
    private let profileService = UserProfileService.shared
    
    @State private var username = ""
    @State private var isLoading = false
    @State private var isLoadingProfile = false
    @State private var message: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Solid black background
                Color.black
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Instructions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Choose a username")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Your username will be displayed as @username throughout the app. It must be 3-20 characters and contain only letters, numbers, and underscores.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Username Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Username")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            HStack {
                                Text("@")
                                    .foregroundColor(.white.opacity(0.7))
                                    .font(.body)
                                
                                TextField("username", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.white.opacity(0.15))
                                    .cornerRadius(8)
                            }
                            
                            if let message = message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(message.contains("success") ? .green : .red)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Save Button
                        Button {
                            updateUsername()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save Username")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            username.isEmpty || !isValidUsername(username) 
                                ? Color.gray.opacity(0.3) 
                                : Color(hex: "#1ED760")
                        )
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .disabled(username.isEmpty || !isValidUsername(username) || isLoading)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Edit Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                await loadProfile()
            }
        }
    }
    
    private func isValidUsername(_ username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        let regex = "^[a-z0-9_]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: trimmed)
    }
    
    private func loadProfile() async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        
        do {
            if let profile = try await profileService.getCurrentUserProfile() {
                username = profile.username ?? ""
            }
        } catch {
            message = "Failed to load profile: \(error.localizedDescription)"
        }
    }
    
    private func updateUsername() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        
        guard !trimmedUsername.isEmpty else {
            message = "Please enter a username"
            return
        }
        
        guard isValidUsername(trimmedUsername) else {
            message = "Username must be 3-20 characters and contain only letters, numbers, and underscores"
            return
        }
        
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                try await profileService.updateUsername(trimmedUsername)
                message = "Username updated successfully"
                
                // Dismiss after a short delay
                try? await Task.sleep(for: .milliseconds(800))
                dismiss()
            } catch {
                let errorMessage = error.localizedDescription
                if errorMessage.contains("already taken") {
                    message = "This username is already taken. Please choose another one."
                } else {
                    message = "Failed to update username: \(errorMessage)"
                }
            }
        }
    }
}

#Preview {
    EditUsernameView()
}

