import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    @Binding var showForgotPassword: Bool

    var body: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                showForgotPassword = true
            } label: {
                Text("Forgot Password?")
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            Button(action: login) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Log In")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .padding(.top, 8)
        }
        .padding()
    }

    private func login() {
        errorMessage = nil
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                try await authVM.login(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
