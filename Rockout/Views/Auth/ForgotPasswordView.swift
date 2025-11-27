import SwiftUI

struct ForgotPasswordView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var email = ""
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {

            Text("Reset Password")
                .font(.title2)
                .bold()

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }

            if let message = message {
                Text(message)
                    .foregroundColor(.green)
            }

            Button {
                Task {
                    do {
                        try await authVM.sendPasswordReset(email: email)
                        message = "Password reset sent!"
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                        message = nil
                    }
                }
            } label: {
                Text("Send Reset Email")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
        }
        .padding()
    }
}
