import SwiftUI
import AuthenticationServices

struct SpotifyConnectionView: View {
    @EnvironmentObject var spotifyAuth: SpotifyAuthService
    @State private var isConnecting = false
    @State private var isDisconnecting = false
    @State private var errorMessage: String?
    @State private var authSession: ASWebAuthenticationSession?
    
    var body: some View {
        VStack(spacing: 20) {
            // Spotify Logo/Icon
            Image(systemName: "music.note")
                .font(.system(size: 50))
                .foregroundColor(Color(red: 0.12, green: 0.72, blue: 0.33)) // Spotify green
                .padding(.top, 20)
            
            if spotifyAuth.isAuthorized(), let connection = spotifyAuth.spotifyConnection {
                // Connected State
                VStack(spacing: 12) {
                    Text("Connected to Spotify")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if let displayName = connection.display_name {
                        Text(displayName)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    if let email = connection.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Button(role: .destructive) {
                        Task {
                            await disconnectSpotify()
                        }
                    } label: {
                        Group {
                            if isDisconnecting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Disconnect Spotify")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .frame(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(12)
                    .disabled(isDisconnecting)
                    
                    Text("This will only disconnect your Spotify account from Rockout. Your Rockout account will remain logged in.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                // Not Connected State
                VStack(spacing: 16) {
                    Text("Connect Your Spotify Account")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Connect to access your Spotify data and recommendations")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button {
                        Task {
                            await connectSpotify()
                        }
                    } label: {
                        Group {
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                HStack {
                                    Image(systemName: "music.note")
                                    Text("Connect to Spotify")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .frame(height: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .padding()
                    .background(Color(red: 0.12, green: 0.72, blue: 0.33)) // Spotify green
                    .cornerRadius(12)
                    .disabled(isConnecting)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding(24)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
    
    private func connectSpotify() async {
        await MainActor.run {
            isConnecting = true
            errorMessage = nil
        }
        
        // Cancel any existing session FIRST
        await MainActor.run {
            if let existingSession = authSession {
                print("🔄 Canceling existing session...")
                existingSession.cancel()
                authSession = nil
            }
        }
        
        // Wait longer for cleanup - iOS needs time to release the session
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        guard let url = spotifyAuth.startAuthorization() else {
            await MainActor.run {
                errorMessage = "Failed to start authorization"
                isConnecting = false
            }
            return
        }
        
        print("🔗 Authorization URL: \(url.absoluteString)")
        
        // Create and configure session
        await MainActor.run {
            let provider = SpotifyPresentationContextProvider()
            
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "rockout"
            ) { callbackURL, error in
                
                Task { @MainActor in
                    self.isConnecting = false
                    self.authSession = nil
                    
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && nsError.code == 2 {
                            print("ℹ️ User canceled Spotify authentication")
                            return
                        }
                        self.errorMessage = "Authorization failed: \(error.localizedDescription)"
                        print("❌ Spotify auth error: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let callbackURL = callbackURL else {
                        print("⚠️ No callback URL received")
                        self.errorMessage = "Authorization completed but no callback URL received"
                        return
                    }
                    
                    print("✅ Spotify callback received: \(callbackURL.absoluteString)")
                    Task {
                        do {
                            try await self.spotifyAuth.handleRedirectURL(callbackURL)
                            await self.spotifyAuth.loadConnection()
                        } catch {
                            await MainActor.run {
                                let nsError = error as NSError
                                if let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                                    self.errorMessage = description
                                } else {
                                    self.errorMessage = error.localizedDescription
                                }
                            }
                            print("❌ Error completing Spotify connection: \(error)")
                        }
                    }
                }
            }
            
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            
            // CRITICAL: Store session BEFORE calling start() to prevent deallocation
            authSession = session
            
            // Ensure we're on main thread and try to start
            print("🚀 Attempting to start ASWebAuthenticationSession...")
            print("🚀 Current app state: \(UIApplication.shared.applicationState.rawValue)")
            
            // Try starting - must be on main thread
            let started = session.start()
            
            if !started {
                print("❌ CRITICAL: session.start() returned false")
                print("❌ Trying fallback: opening URL directly...")
                authSession = nil
                
                // Fallback: Try opening URL directly
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url) { success in
                        Task { @MainActor in
                            if success {
                                print("✅ Opened URL directly - user will need to manually return to app")
                                self.isConnecting = false
                            } else {
                                print("❌ Failed to open URL directly too")
                                self.errorMessage = "Cannot start authentication. Please quit the app completely and try again."
                                self.isConnecting = false
                            }
                        }
                    }
                } else {
                    errorMessage = "Cannot start authentication. Another session may be active. Please quit the app completely and try again."
                    isConnecting = false
                }
            } else {
                print("✅ Session started successfully! Browser should open now...")
            }
        }
    }
    
    private func disconnectSpotify() async {
        isDisconnecting = true
        errorMessage = nil
        
        // Disconnect from Spotify
        await spotifyAuth.disconnect()
        
        // Reload connection state
        await spotifyAuth.loadConnection()
        
        isDisconnecting = false
    }
}

