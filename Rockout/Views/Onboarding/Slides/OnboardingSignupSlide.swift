import SwiftUI

struct OnboardingSignupSlide: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Binding var hasSeenOnboarding: Bool
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var username = ""
    @State private var errorMessage: String?
    @State private var isSigningUp = false
    
    @FocusState private var focusedField: SignupField?
    
    enum SignupField {
        case firstName, lastName, email, password, confirmPassword, username
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 40)
                
                // Title and subtitle
                VStack(spacing: 12) {
                    Text("Create your Rockout account")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(1.0)
                        .multilineTextAlignment(.center)
                    
                    Text("Lock in your SoundPrint, climb RockLists, join GreenRoom, and enter Studio Sessions.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 20)
                
                // Form container (glassmorphism)
                VStack(spacing: 16) {
                    OnboardingTextField(
                        placeholder: "First Name",
                        text: $firstName
                    )
                    .focused($focusedField, equals: .firstName)
                    
                    OnboardingTextField(
                        placeholder: "Last Name",
                        text: $lastName
                    )
                    .focused($focusedField, equals: .lastName)
                    
                    OnboardingTextField(
                        placeholder: "Username",
                        text: $username,
                        keyboardType: .default,
                        autocapitalization: .never
                    )
                    .focused($focusedField, equals: .username)
                    
                    OnboardingTextField(
                        placeholder: "Email",
                        text: $email,
                        keyboardType: .emailAddress,
                        autocapitalization: .never
                    )
                    .focused($focusedField, equals: .email)
                    
                    OnboardingTextField(
                        placeholder: "Password",
                        text: $password,
                        isSecure: true
                    )
                    .focused($focusedField, equals: .password)
                    
                    OnboardingTextField(
                        placeholder: "Confirm Password",
                        text: $confirmPassword,
                        isSecure: true
                    )
                    .focused($focusedField, equals: .confirmPassword)
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.top, 8)
                    }
                    
                    // Create Account button
                    Button {
                        Task {
                            await handleSignup()
                        }
                    } label: {
                        HStack {
                            if isSigningUp {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Create Account")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(
                                colors: [Color.brandPurple, Color.brandBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(25)
                        .shadow(color: Color.brandPurple.opacity(0.4), radius: 10)
                    }
                    .disabled(isSigningUp || !isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.6)
                    .padding(.top, 8)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.brandPurple.opacity(0.5), Color.brandBlue.opacity(0.5)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                )
                .shadow(color: Color.brandPurple.opacity(0.2), radius: 20)
                .padding(.horizontal, 32)
                
                // Login link
                Button {
                    // Mark onboarding as seen and show login
                    hasSeenOnboarding = true
                    OnboardingState.shared.markOnboardingComplete()
                } label: {
                    Text("Already have an account? Log in")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }
    
    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }
    
    private func handleSignup() async {
        errorMessage = nil
        isSigningUp = true
        
        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespaces)
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        
        // Validation
        guard !trimmedFirstName.isEmpty, !trimmedLastName.isEmpty else {
            errorMessage = "Please enter your first and last name"
            isSigningUp = false
            return
        }
        
        guard !trimmedUsername.isEmpty else {
            errorMessage = "Please enter a username"
            isSigningUp = false
            return
        }
        
        // Validate username format
        let usernameRegex = "^[a-z0-9_]{3,20}$"
        let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        guard usernamePredicate.evaluate(with: trimmedUsername) else {
            errorMessage = "Username must be 3-20 characters and contain only letters, numbers, and underscores"
            isSigningUp = false
            return
        }
        
        // Validate email format
        guard trimmedEmail.contains("@") && trimmedEmail.contains(".") else {
            errorMessage = "Please enter a valid email address"
            isSigningUp = false
            return
        }
        
        // Validate password
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            isSigningUp = false
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            isSigningUp = false
            return
        }
        
        // Signup
        do {
            try await authVM.signup(email: trimmedEmail, password: password)
            try await authVM.login(email: trimmedEmail, password: password)
            
            // Create user profile
            try await UserProfileService.shared.createOrUpdateProfile(
                firstName: trimmedFirstName,
                lastName: trimmedLastName,
                username: trimmedUsername
            )
            
            // Mark onboarding as complete
            hasSeenOnboarding = true
            OnboardingState.shared.markOnboardingComplete()
            
        } catch {
            errorMessage = formatAuthError(error)
            isSigningUp = false
        }
    }
    
    private func formatAuthError(_ error: Error) -> String {
        let nsError = error as NSError
        let message = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
        let lowercased = message.lowercased()
        
        if lowercased.contains("username is already taken") || lowercased.contains("username already") {
            return "This username is already taken. Please choose another one."
        }
        
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
        
        return message
    }
}

