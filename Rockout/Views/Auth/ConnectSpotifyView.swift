import SwiftUI

struct ConnectSpotifyView: View {
    @EnvironmentObject var authService: SpotifyAuthService
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Connect your Spotify account")
                .font(.title)
                .bold()
            
            Button {
                if let url = authService.startAuthorization() {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Connect to Spotify")
                    .bold()
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
    }
}
