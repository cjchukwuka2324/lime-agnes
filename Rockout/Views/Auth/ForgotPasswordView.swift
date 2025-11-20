import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var email = ""
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {

                Text("Reset Password")
                    .font(.title)
                    .bold()

                TextField("Enter your email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)

                if let message = message {
                    Text(message)
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.center)
                }

                Button(action: resetPassword) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("Send Reset Link")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .disabled(isLoading || email.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Forgot Password")
        }
    }

    private func resetPassword() {
        message = nil
        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                try await authVM.sendPasswordReset(email: email)
                message = "If an account exists for \(email), a reset link has been sent."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
