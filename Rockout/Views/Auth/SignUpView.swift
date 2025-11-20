import SwiftUI

struct SignupView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let message = message {
                Text(message)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
            }

            Button(action: signup) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Create Account")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .padding(.top, 8)
        }
        .padding()
    }

    private func signup() {
        message = nil
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await authVM.signup(email: email, password: password)
                message = "Check your email to confirm your account (if required)."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
