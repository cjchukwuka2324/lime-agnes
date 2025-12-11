import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
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
