import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("Set New Password")
                .font(.title)
                .bold()

            SecureField("New Password", text: $newPassword)
                .textFieldStyle(.roundedBorder)

            SecureField("Confirm Password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)

            if let message = message {
                Text(message)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
            }

            Button(action: updatePassword) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Update Password")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .disabled(isLoading || newPassword.isEmpty || confirmPassword.isEmpty)

            Spacer()
        }
        .padding()
    }

    private func updatePassword() {
        guard newPassword == confirmPassword else {
            message = "Passwords do not match."
            return
        }

        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                try await authVM.updatePassword(to: newPassword)
                message = "Password updated. You are now logged in."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

#Preview { ResetPasswordView() }
