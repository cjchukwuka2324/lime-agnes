import SwiftUI

struct GoogleLoginButton: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        Button {
            Task {
                do {
                    print("🌐 Starting Supabase Mobile OAuth (Google)…")

                    let _ = try await SupabaseService.shared.client.auth.signInWithOAuth(
                        provider: .google,
                        redirectTo: URL(string: "rockout://auth/callback")!
                    )

                    print("➡️ Redirecting to Google…")
                } catch {
                    print("❌ Google OAuth failed:", error)
                }
            }
        } label: {
            HStack {
                Image("google-logo")
                    .resizable()
                    .frame(width: 20, height: 20)

                Text("Continue with Google")
                    .fontWeight(.semibold)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .foregroundColor(.black)
            .cornerRadius(8)
        }
    }
}
