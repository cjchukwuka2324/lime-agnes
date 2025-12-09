import SwiftUI

struct SignUpForm: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
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

            TextField("Username", text: $username)
                .textInputAutocapitalization(.never)
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

            SecureField("Password", text: $password)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }

            Button {
                Task {
                    errorMessage = nil
                    let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
                    let trimmedLastName = lastName.trimmingCharacters(in: .whitespaces)
                    let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
                    
                    guard !trimmedFirstName.isEmpty,
                          !trimmedLastName.isEmpty else {
                        errorMessage = "Please enter your first and last name"
                        return
                    }
                    
                    guard !trimmedUsername.isEmpty else {
                        errorMessage = "Please enter a username"
                        return
                    }
                    
                    // Validate username format (alphanumeric and underscore only, 3-20 characters)
                    let usernameRegex = "^[a-z0-9_]{3,20}$"
                    let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
                    guard usernamePredicate.evaluate(with: trimmedUsername) else {
                        errorMessage = "Username must be 3-20 characters and contain only letters, numbers, and underscores"
                        return
                    }
                    
                    do {
                        try await authVM.signup(email: email, password: password)
                        try await authVM.login(email: email, password: password)
                        
                        // Create user profile with first name, last name, username, and email
                        try await UserProfileService.shared.createOrUpdateProfile(
                            firstName: trimmedFirstName,
                            lastName: trimmedLastName,
                            username: trimmedUsername,
                            email: email
                        )
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
            .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || 
                     lastName.trimmingCharacters(in: .whitespaces).isEmpty ||
                     username.trimmingCharacters(in: .whitespaces).isEmpty)
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
