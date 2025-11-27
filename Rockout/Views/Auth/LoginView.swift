import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showSignUp = false
    @State private var showForgotPassword = false

    var body: some View {
        VStack(spacing: 30) {

            LoginForm()

            Button("Forgot password?") {
                showForgotPassword = true
            }
            .foregroundColor(.blue)

            Button("Create an Account") {
                showSignUp = true
            }
            .foregroundColor(.blue)

            // Google Login Button
            Button {
                authVM.loginWithGoogle()
            } label: {
                HStack {
                    Image(systemName: "globe")
                    Text("Continue with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
        }
        .padding()
        .sheet(isPresented: $showSignUp) {
            SignUpView()
                .environmentObject(authVM)
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
                .environmentObject(authVM)
        }
    }
}
