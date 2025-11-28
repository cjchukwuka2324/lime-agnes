import Foundation
import Combine

@MainActor
final class SpotifyAuthService: ObservableObject {

    static let shared = SpotifyAuthService()

    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var expirationDate: Date?
    @Published private(set) var spotifyConnection: SpotifyConnection?
    @Published private(set) var isLoading = false

    private let clientID = "13aa07c310bb445d82fc8035ee426d0c"
    private let redirectURI = "rockout://auth"
    private let tokenURL = "https://accounts.spotify.com/api/token"
    private let scopes = "user-read-email user-read-private user-top-read"
    private let connectionService = SpotifyConnectionService.shared

    private init() {
        Task {
            await loadConnection()
        }
    }
    
    // MARK: - Load Connection from Database
    func loadConnection() async {
        isLoading = true
        defer { isLoading = false }
        
        // First clear any stale local tokens
        SpotifyTokenStore.clear()
        
        do {
            if let connection = try await connectionService.getConnection() {
                spotifyConnection = connection
                accessToken = connection.access_token
                refreshToken = connection.refresh_token
                
                let formatter = ISO8601DateFormatter()
                if let expiresAt = formatter.date(from: connection.expires_at) {
                    expirationDate = expiresAt
                    
                    // Also save to local storage for offline access
                    let timeUntilExpiry = Int(expiresAt.timeIntervalSinceNow)
                    let tokens = SpotifyTokens(
                        access_token: connection.access_token,
                        token_type: "Bearer",
                        scope: nil,
                        expires_in: max(timeUntilExpiry, 3600), // At least 1 hour if negative
                        refresh_token: connection.refresh_token
                    )
                    SpotifyTokenStore.saveTokens(tokens, expiry: expiresAt)
                }
            } else {
                // No connection in database - make sure local storage is clear too
                SpotifyTokenStore.clear()
                accessToken = nil
                refreshToken = nil
                expirationDate = nil
                spotifyConnection = nil
            }
        } catch {
            print("Failed to load Spotify connection: \(error)")
            // Clear everything if we can't load
            SpotifyTokenStore.clear()
            accessToken = nil
            refreshToken = nil
            expirationDate = nil
            spotifyConnection = nil
        }
    }

    func isAuthorized() -> Bool {
        guard let a = accessToken, !a.isEmpty,
              let e = expirationDate else { return false }
        return Date() < e
    }

    func startAuthorization() -> URL? {
        let verifier = String.random(length: 64)
        let challenge = verifier.sha256Base64URL()
        SpotifyTokenStore.saveVerifier(verifier)

        var c = URLComponents(string: "https://accounts.spotify.com/authorize")
        c?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: scopes)
        ]
        return c?.url
    }

    func handleRedirectURL(_ url: URL) async throws {
        print("🔗 Spotify redirect URL received: \(url.absoluteString)")
        print("🔗 URL scheme: \(url.scheme ?? "nil")")
        print("🔗 URL host: \(url.host ?? "nil")")
        print("🔗 URL path: \(url.path)")
        print("🔗 URL query: \(url.query ?? "nil")")
        
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            let error = NSError(
                domain: "SpotifyAuth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid redirect URL format: \(url.absoluteString)"]
            )
            print("❌ ERROR -1: Invalid redirect URL format")
            print("❌ Full URL: \(url.absoluteString)")
            throw error
        }
        
        print("🔗 Query items: \(c.queryItems?.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: ", ") ?? "nil")")
        
        // Check for error in callback
        if let errorParam = c.queryItems?.first(where: { $0.name == "error" })?.value {
            let error = NSError(
                domain: "SpotifyAuth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Spotify OAuth error: \(errorParam)"]
            )
            print("❌ ERROR -1: Spotify OAuth error in callback")
            print("❌ Error parameter: \(errorParam)")
            throw error
        }
        
        guard let code = c.queryItems?.first(where: { $0.name == "code" })?.value else {
            let error = NSError(
                domain: "SpotifyAuth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No authorization code in redirect URL. URL: \(url.absoluteString)"]
            )
            print("❌ ERROR -1: No authorization code in redirect URL")
            print("❌ Available query items: \(c.queryItems?.map { $0.name }.joined(separator: ", ") ?? "none")")
            throw error
        }
        
        print("✅ Got authorization code, code length: \(code.count)")
        print("✅ Exchanging code for tokens...")
        try await exchangeCode(code)
    }

    private func exchangeCode(_ code: String) async throws {
        print("🔄 exchangeCode called, code length: \(code.count)")
        
        guard let verifier = SpotifyTokenStore.loadVerifier() else {
            let error = NSError(
                domain: "SpotifyAuth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing code verifier. Please try connecting again."]
            )
            print("❌ ERROR -1: Missing code verifier")
            print("❌ This means the PKCE verifier was not saved or was cleared")
            throw error
        }
        
        print("✅ Verifier found, length: \(verifier.count)")

        let body = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ]
        
        print("🔄 Sending token request to Spotify...")
        print("🔄 Redirect URI: \(redirectURI)")

        do {
            let tokens = try await tokenRequest(body)
            print("✅ Successfully exchanged code for tokens")
            print("✅ Access token received, length: \(tokens.access_token.count)")
            await saveToDatabase(tokens, isRefresh: false)
            print("✅ Spotify connection saved successfully")
        } catch {
            print("❌ ERROR in exchangeCode: \(error)")
            print("❌ Error domain: \((error as NSError).domain)")
            print("❌ Error code: \((error as NSError).code)")
            print("❌ Error details: \(error.localizedDescription)")
            
            if let nsError = error as NSError? {
                if nsError.userInfo.count > 0 {
                    print("❌ Error userInfo: \(nsError.userInfo)")
                }
            }
            
            // Re-throw the error so it can be handled by the caller
            throw error
        }
    }

    func refreshAccessTokenIfNeeded() async throws -> String {
        print("🔄 refreshAccessTokenIfNeeded called")
        
        // Check if we have a valid token
        if let e = expirationDate, e > Date(), let token = accessToken, !token.isEmpty {
            print("✅ Token still valid, expiry: \(e)")
            return token
        }
        
        print("⚠️ Token expired or missing, attempting refresh...")
        print("⚠️ Has expirationDate: \(expirationDate != nil)")
        print("⚠️ Has accessToken: \(accessToken != nil)")
        print("⚠️ Access token length: \(accessToken?.count ?? 0)")
        
        // Try to refresh
        do {
            let newToken = try await refresh()
            print("✅ Token refreshed successfully")
            return newToken
        } catch {
            print("❌ Token refresh failed: \(error.localizedDescription)")
            print("❌ Error domain: \((error as NSError).domain)")
            print("❌ Error code: \((error as NSError).code)")
            
            // If refresh fails, try to load from database
            print("🔄 Attempting to load connection from database...")
            await loadConnection()
            
            // Try again with loaded connection
            if let token = accessToken, !token.isEmpty, let e = expirationDate, e > Date() {
                print("✅ Got token from database")
                return token
            }
            
            // Still no token - throw a clearer error
            let error = NSError(
                domain: "SpotifyAuth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated with Spotify. Please connect your Spotify account in Profile settings."]
            )
            throw error
        }
    }

    private func refresh() async throws -> String {
        guard let r = refreshToken else {
            throw NSError(domain: "SpotifyAuth", code: -1)
        }

        let body = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": r
        ]

        let t = try await tokenRequest(body)
        await saveToDatabase(t, isRefresh: true)
        return t.access_token
    }

    private func tokenRequest(_ body: [String : String]) async throws -> SpotifyTokens {
        print("🌐 tokenRequest called, URL: \(tokenURL)")
        
        guard let url = URL(string: tokenURL) else {
            let error = NSError(
                domain: "SpotifyAuth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid token URL: \(tokenURL)"]
            )
            print("❌ ERROR -1: Invalid token URL")
            print("❌ Token URL string: \(tokenURL)")
            throw error
        }
        
        print("✅ Token URL is valid")

        let b = body.percentEncoded()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = b.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "SpotifyAuth", code: -2)
        }

        if http.statusCode != 200 {
            let bodyStr = String(data: data, encoding: .utf8) ?? "error"
            throw NSError(domain: "SpotifyAuth", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: bodyStr])
        }

        return try JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    // MARK: - Save to Database
    private func saveToDatabase(_ t: SpotifyTokens, isRefresh: Bool = false) async {
        accessToken = t.access_token
        refreshToken = t.refresh_token ?? refreshToken

        let expiry = Date().addingTimeInterval(Double(t.expires_in))
        expirationDate = expiry

        // Also save locally for offline access
        SpotifyTokenStore.saveTokens(t, expiry: expiry)
        
        // If we already have a connection, just update tokens
        if isRefresh, let existingConnection = spotifyConnection {
            do {
                try await connectionService.updateTokens(
                    accessToken: t.access_token,
                    refreshToken: t.refresh_token,
                    expiresAt: expiry
                )
                // Update local connection object
                var updated = existingConnection
                // Note: We can't mutate the struct directly, so we'll reload
                await loadConnection()
            } catch {
                print("Failed to update tokens: \(error)")
            }
            return
        }
        
        // New connection - get Spotify user profile
        do {
            // Make direct API call to get user profile
            let profile = try await fetchSpotifyProfile(accessToken: t.access_token)
            
            // Save to database
            let connection = try await connectionService.saveConnection(
                spotifyUserId: profile.id,
                accessToken: t.access_token,
                refreshToken: t.refresh_token ?? refreshToken ?? "",
                expiresAt: expiry,
                displayName: profile.display_name,
                email: profile.email
            )
            
            spotifyConnection = connection
            // RockList ingestion is automatically triggered from RootAppView and RockOutApp
            // when authentication state changes, avoiding circular dependencies
        } catch {
            print("Failed to save Spotify connection: \(error)")
            // Still save tokens even if profile fetch fails
            if let refreshToken = t.refresh_token ?? refreshToken {
                try? await connectionService.saveConnection(
                    spotifyUserId: "unknown",
                    accessToken: t.access_token,
                    refreshToken: refreshToken,
                    expiresAt: expiry
                )
            }
        }
    }
    
    // MARK: - Fetch Spotify Profile
    private func fetchSpotifyProfile(accessToken: String) async throws -> SpotifyUserProfile {
        guard let url = URL(string: "https://api.spotify.com/v1/me") else {
            let error = NSError(
                domain: "SpotifyAuth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid profile API URL"]
            )
            print("❌ Profile fetch failed: \(error.localizedDescription)")
            throw error
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let http = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: "SpotifyAuth",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
                )
                print("❌ Profile fetch failed: \(error.localizedDescription)")
                throw error
            }
            
            guard (200...299).contains(http.statusCode) else {
                let bodyStr = String(data: data, encoding: .utf8) ?? "Unknown error"
                let error = NSError(
                    domain: "SpotifyAuth",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(bodyStr)"]
                )
                print("❌ Profile fetch failed: HTTP \(http.statusCode) - \(bodyStr)")
                throw error
            }
            
            return try JSONDecoder().decode(SpotifyUserProfile.self, from: data)
        } catch {
            print("❌ Profile fetch network error: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Disconnect Spotify
    func disconnect() async {
        // Clear local state first
        accessToken = nil
        refreshToken = nil
        expirationDate = nil
        spotifyConnection = nil
        SpotifyTokenStore.clear()
        
        // Try to delete from database (ignore errors if not connected or no session)
        do {
            try await connectionService.deleteConnection()
        } catch {
            // Ignore errors - connection might not exist or user might not be logged in
            print("Note: Could not delete Spotify connection from database (might not exist): \(error.localizedDescription)")
        }
    }
}
