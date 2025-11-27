import SwiftUI

struct LoginForm: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {

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
                    do {
                        try await authVM.login(email: email, password: password)
                    } catch {
                        // Provide user-friendly error messages
                        let nsError = error as NSError
                        if let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                            errorMessage = formatLoginError(description)
                        } else {
                            errorMessage = formatLoginError(error.localizedDescription)
                        }
                    }
                }
            } label: {
                Text("Log In")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Error Formatting
    
    private func formatLoginError(_ message: String) -> String {
        let lowercased = message.lowercased()
        
        if lowercased.contains("invalid") && (lowercased.contains("credentials") || lowercased.contains("password") || lowercased.contains("email")) {
            return "Invalid email or password. Please check and try again."
        }
        
        if lowercased.contains("user not found") || lowercased.contains("no account") {
            return "No account found with this email. Please sign up first."
        }
        
        if lowercased.contains("email not confirmed") || lowercased.contains("verify") {
            return "Please check your email and confirm your account before signing in."
        }
        
        if lowercased.contains("network") || lowercased.contains("connection") {
            return "Network error. Please check your internet connection and try again."
        }
        
        return message
    }
}
