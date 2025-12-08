import SwiftUI

struct AuthFlowView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedTab: AuthTab = .login

    var body: some View {
        VStack(spacing: 28) {

            // LOGO
            VStack(spacing: 6) {
                Image("authicon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                Text("RockOut")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.top, 48)

            // TABS
            Picker("Auth Tabs", selection: $selectedTab) {
                Text("Login").tag(AuthTab.login)
                Text("Sign Up").tag(AuthTab.signup)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // FORMS
            VStack {
                switch selectedTab {
                case .login:
                    LoginForm()
                case .signup:
                    SignUpForm()
                }
            }
            .padding(.horizontal)

            // GOOGLE BUTTON
            GoogleLoginButton()
                .padding(.horizontal)

            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
    }
}

enum AuthTab {
    case login
    case signup
}
