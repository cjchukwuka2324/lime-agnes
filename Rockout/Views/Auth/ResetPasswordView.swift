import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
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
                            Text("Set a new password")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Your new password should be at least 8 characters long and contain a mix of letters, numbers, and special characters.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Password Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("New Password")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            SecureField("Enter new password", text: $newPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                            
                            Text("Confirm Password")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.top, 8)
                            
                            SecureField("Confirm new password", text: $confirmPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                            
                            if let message = message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(message.contains("success") || message.contains("updated") ? .green : .red)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Update Button
                        Button {
                            updatePassword()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Update Password")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            newPassword.isEmpty || confirmPassword.isEmpty || newPassword != confirmPassword
                                ? Color.gray.opacity(0.3) 
                                : Color(hex: "#1ED760")
                        )
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .disabled(newPassword.isEmpty || confirmPassword.isEmpty || newPassword != confirmPassword || isLoading)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Set New Password")
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
        }
    }

    private func updatePassword() {
        guard newPassword == confirmPassword else {
            message = "Passwords do not match."
            return
        }
        
        guard newPassword.count >= 8 else {
            message = "Password must be at least 8 characters long."
            return
        }

        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                try await authVM.updatePassword(to: newPassword)
                message = "Password updated successfully"
                
                // Dismiss after a short delay
                try? await Task.sleep(for: .milliseconds(800))
                dismiss()
            } catch {
                message = "Failed to update password: \(error.localizedDescription)"
            }
        }
    }
}

#Preview { 
    ResetPasswordView()
        .environmentObject(AuthViewModel())
}
