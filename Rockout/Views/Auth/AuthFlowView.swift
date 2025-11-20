import SwiftUI

struct AuthFlowView: View {
    enum Tab {
        case login
        case signup
    }

    @State private var selectedTab: Tab = .login
    @State private var showForgotPassword = false

    var body: some View {
        NavigationStack {
            VStack {
                Picker("", selection: $selectedTab) {
                    Text("Log In").tag(Tab.login)
                    Text("Sign Up").tag(Tab.signup)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                switch selectedTab {
                case .login:
                    LoginView(showForgotPassword: $showForgotPassword)
                case .signup:
                    SignupView()
                }

                Spacer()
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
            .navigationTitle("RockOut")
        }
    }
}
