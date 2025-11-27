import SwiftUI

struct SignUpForm: View {
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
                    do {
                        try await authVM.signup(email: email, password: password)
                        try await authVM.login(email: email, password: password)
                    } catch {
                        errorMessage = error.localizedDescription
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
        }
    }
}
