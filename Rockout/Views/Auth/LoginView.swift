import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showSignUp = false
    @State private var showForgotPassword = false

    var body: some View {
        VStack(spacing: 30) {
            // Logo and Title
            VStack(spacing: 6) {
                Image("authIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                Text("RockOut")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.top, 20)

            LoginForm()

            Button("Forgot password?") {
                showForgotPassword = true
            }
            .foregroundColor(.blue)

            Button("Create an Account") {
                showSignUp = true
            }
            .foregroundColor(.blue)
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
