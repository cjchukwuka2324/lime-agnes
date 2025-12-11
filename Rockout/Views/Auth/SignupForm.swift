import SwiftUI

struct SignUpForm: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            TextField("First Name", text: $firstName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            
            TextField("Last Name", text: $lastName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 8) {
                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                if !password.isEmpty {
                    Text(password.count < 6 ? "Password must be at least 6 characters" : "✓ Password meets requirements")
                        .font(.caption)
                        .foregroundColor(password.count < 6 ? .red : .green)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                SecureField("Confirm Password", text: $confirmPassword)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                if !confirmPassword.isEmpty && !password.isEmpty {
                    if password != confirmPassword {
                        Text("Passwords do not match")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else {
                        Text("✓ Passwords match")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            if let errorMessage = errorMessage {
                let messageType: MessageType = errorMessage.lowercased().contains("check your email") || errorMessage.lowercased().contains("account created") ? .info : .error
                ErrorMessageBanner(errorMessage, type: messageType)
            }

            Button {
                Task {
                    errorMessage = nil
                    let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
                    let trimmedLastName = lastName.trimmingCharacters(in: .whitespaces)
                    
                    guard !trimmedFirstName.isEmpty,
                          !trimmedLastName.isEmpty else {
                        errorMessage = "Please enter your first and last name"
                        return
                    }
                    
                    // Validate password
                    guard !password.isEmpty else {
                        errorMessage = "Please enter a password"
                        return
                    }
                    
                    guard password.count >= 6 else {
                        errorMessage = "Password must be at least 6 characters long"
                        return
                    }
                    
                    guard password == confirmPassword else {
                        errorMessage = "Passwords do not match"
                        return
                    }
                    
                    do {
                        // Step 1: Sign up the user and get the user ID
                        let userId = try await authVM.signup(email: email, password: password)
                        
                        // Step 2: Try to login immediately after signup (may fail if email confirmation required)
                        var hasActiveSession = false
                        do {
                            try await authVM.login(email: email, password: password)
                            hasActiveSession = true
                        } catch {
                            // Login failed - likely email confirmation required
                            print("⚠️ Login failed after signup: \(error.localizedDescription)")
                        }
                        
                        // Step 3: Update user profile with the provided data
                        // If we have a session, update now. Otherwise, save for later update
                        if hasActiveSession {
                            do {
                                try await UserProfileService.shared.createOrUpdateProfileAfterSignup(
                                    userId: userId,
                                    firstName: trimmedFirstName,
                                    lastName: trimmedLastName,
                                    email: email
                                )
                                print("✅ Profile created successfully with name")
                                // Username setup will be handled automatically by RootAppView routing
                                errorMessage = "Account created! Please set your username to continue."
                            } catch {
                                // Profile update failed, but account is created
                                print("⚠️ Profile update failed: \(error.localizedDescription)")
                                // Save for later update
                                UserProfileService.shared.savePendingSignupData(
                                    userId: userId,
                                    firstName: trimmedFirstName,
                                    lastName: trimmedLastName,
                                    email: email
                                )
                                errorMessage = "Account created! Please check your email and confirm your account. Your profile will be updated when you log in."
                            }
                        } else {
                            // Email confirmation required - save profile data for later update
                            UserProfileService.shared.savePendingSignupData(
                                userId: userId,
                                firstName: trimmedFirstName,
                                lastName: trimmedLastName,
                                email: email
                            )
                            errorMessage = "Account created! Please check your email and confirm your account. Your profile will be updated when you log in."
                        }
                    } catch {
                        // Provide user-friendly error messages
                        errorMessage = formatAuthError(error)
                    }
                }
            } label: {
                Text("Create Account")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
            .disabled(
                firstName.trimmingCharacters(in: .whitespaces).isEmpty || 
                lastName.trimmingCharacters(in: .whitespaces).isEmpty ||
                password.isEmpty ||
                confirmPassword.isEmpty ||
                password.count < 6 ||
                password != confirmPassword
            )
        }
    }
    
    // MARK: - Error Formatting
    
    private func formatAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        let message = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
        let lowercased = message.lowercased()
        
        // Check for username already taken
        if lowercased.contains("username is already taken") || lowercased.contains("username already") {
            return "This username is already taken. Please choose another one."
        }
        
        // Check for common Supabase/Supabase auth errors
        if lowercased.contains("email already") || lowercased.contains("user already exists") || lowercased.contains("already registered") {
            return "An account with this email already exists. Please log in instead."
        }
        
        if lowercased.contains("invalid email") || lowercased.contains("email format") {
            return "Please enter a valid email address."
        }
        
        if lowercased.contains("password") && (lowercased.contains("weak") || lowercased.contains("too short") || lowercased.contains("minimum")) {
            return "Password is too weak. Please use at least 6 characters."
        }
        
        if lowercased.contains("network") || lowercased.contains("connection") || lowercased.contains("timeout") {
            return "Network error. Please check your internet connection and try again."
        }
        
        if lowercased.contains("email not confirmed") || lowercased.contains("verify") || lowercased.contains("confirmation") {
            return "Please check your email and confirm your account before signing in."
        }
        
        // Return formatted message
        return message
    }
}
