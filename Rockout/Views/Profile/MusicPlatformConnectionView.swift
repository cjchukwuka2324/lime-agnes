import SwiftUI
import AuthenticationServices

struct MusicPlatformConnectionView: View {
    @StateObject private var spotifyAuth = SpotifyAuthService.shared
    @State private var isConnectingSpotify = false
    @State private var errorMessage: String?
    @State private var authSession: ASWebAuthenticationSession?
    @State private var currentPlatform: String? = nil
    
    var body: some View {
        VStack(spacing: 20) {
            // Determine current connection status
            if let platform = currentPlatform {
                // Connected State
                connectedStateView(platform: platform)
            } else {
                // Not Connected State - show platform options
                notConnectedStateView
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding(24)
        .background(Color.black)
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .task {
            await loadConnectionStatus()
        }
    }
    
    // MARK: - Connected State View
    
    @ViewBuilder
    private func connectedStateView(platform: String) -> some View {
        if platform == "spotify" {
            VStack(spacing: 12) {
                Image("spotify-icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .padding(.top, 20)
                
                Text("Connected to Spotify")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                
                if let connection = spotifyAuth.spotifyConnection {
                    if let displayName = connection.display_name {
                        Text(displayName)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    if let email = connection.email {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(email)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                
                Text("Music streaming platform connection is permanent and cannot be changed.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Not Connected State View
    
    private var notConnectedStateView: some View {
        VStack(spacing: 16) {
            Text("Connect Your Music Platform")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
            Text("Connect your music platform of choice to your RockOut account. This connection is permanent and cannot be changed.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Spotify Button
            Button {
                Task {
                    await connectSpotify()
                }
            } label: {
                Group {
                    if isConnectingSpotify {
                        ProgressView()
                            .tint(Color(red: 0.12, green: 0.72, blue: 0.33))
                    } else {
                        HStack(spacing: 12) {
                            Image("spotify-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("Connect to Spotify")
                                .fontWeight(.semibold)
                                .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33))
                        }
                    }
                }
                .frame(height: 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .padding()
            .background(Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 0.12, green: 0.72, blue: 0.33), lineWidth: 2)
            )
            .cornerRadius(12)
            .disabled(isConnectingSpotify)
        }
    }
    
    // MARK: - Connection Methods
    
    private func loadConnectionStatus() async {
        do {
            let connectionService = MusicPlatformConnectionService.shared
            if let connection = try await connectionService.getConnection() {
                await MainActor.run {
                    currentPlatform = connection.platform
                }
                // Load the appropriate auth service
                if connection.platform == "spotify" {
                    await spotifyAuth.loadConnection()
                }
            }
        } catch {
            print("Failed to load connection status: \(error)")
        }
    }
    
    private func connectSpotify() async {
        await MainActor.run {
            isConnectingSpotify = true
            errorMessage = nil
        }
        
        // Cancel any existing session FIRST
        await MainActor.run {
            if let existingSession = authSession {
                existingSession.cancel()
                authSession = nil
            }
        }
        
        // Wait for cleanup
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        guard let url = spotifyAuth.startAuthorization() else {
            await MainActor.run {
                errorMessage = "Failed to start authorization"
                isConnectingSpotify = false
            }
            return
        }
        
        await MainActor.run {
            let provider = SpotifyPresentationContextProvider()
            
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "rockout"
            ) { callbackURL, error in
                Task { @MainActor in
                    self.isConnectingSpotify = false
                    self.authSession = nil
                    
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && nsError.code == 2 {
                            return // User canceled
                        }
                        self.errorMessage = "Authorization failed: \(error.localizedDescription)"
                        return
                    }
                    
                    guard let callbackURL = callbackURL else {
                        self.errorMessage = "Authorization completed but no callback URL received"
                        return
                    }
                    
                    do {
                        try await self.spotifyAuth.handleRedirectURL(callbackURL)
                        await self.spotifyAuth.loadConnection()
                        await self.loadConnectionStatus()
                    } catch {
                        if let nsError = error as NSError?,
                           nsError.domain == "MusicPlatformConnectionService",
                           nsError.code == -1 {
                            self.errorMessage = "You already have a connection to another platform. Platform connections are permanent."
                        } else {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            _ = session.start()
        }
    }
}

