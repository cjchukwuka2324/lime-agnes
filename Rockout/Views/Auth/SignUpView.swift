import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Create your account")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                SignUpForm()
                    .environmentObject(authVM)
            }
            .padding()
        }
        .navigationTitle("Sign Up")
    }
}
