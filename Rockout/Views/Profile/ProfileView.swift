import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Account")) {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(authVM.currentUserEmail ?? "Unknown")
                            .foregroundColor(.secondary)
                    }

                    NavigationLink("Change Password") {
                        ResetPasswordView()
                    }

                    Button(role: .destructive) {
                        logout()
                    } label: {
                        Text("Log Out")
                    }
                }

                if let message = message {
                    Section {
                        Text(message)
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                await authVM.refreshUser()
            }
        }
    }

    private func logout() {
        Task {
            isLoading = true
            defer { isLoading = false }
            await authVM.logout()
            message = "Logged out."
        }
    }
}
