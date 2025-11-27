import Foundation
import Combine

@MainActor
final class SpotifyAuthService: ObservableObject {

    static let shared = SpotifyAuthService()

    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var expirationDate: Date?
    
    /// Published property for tokens (for compatibility)
    var tokens: SpotifyTokens? {
        guard let access = accessToken else { return nil }
        return SpotifyTokens(
            access_token: access,
            token_type: "Bearer",
            scope: scopes,
            expires_in: Int(expirationDate?.timeIntervalSinceNow ?? 3600),
            refresh_token: refreshToken
        )
    }

    private let clientID = "0d1441ca6ac6428f83b8980295fe7f14"
    private let redirectURI = "rockout://spotify-callback"
    private let tokenURL = "https://accounts.spotify.com/api/token"
    private let scopes = "user-read-email user-read-private user-top-read user-read-recently-played user-follow-read"

    private init() {
        if let (t, expiry) = SpotifyTokenStore.loadTokens() {
            accessToken = t.access_token
            refreshToken = t.refresh_token
            expirationDate = expiry
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

    func handleRedirectURL(_ url: URL) async {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = c.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }

        await exchangeCode(code)
    }

    private func exchangeCode(_ code: String) async {
        guard let verifier = SpotifyTokenStore.loadVerifier() else { return }

        let body = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ]

        do {
            let tokens = try await tokenRequest(body)
            save(tokens)
        } catch {
            print("Exchange error:", error)
        }
    }

    func refreshAccessTokenIfNeeded() async throws -> String {
        // If we have a valid token, return it
        if let e = expirationDate, e > Date(), let token = accessToken, !token.isEmpty {
            return token
        }
        
        // If we have a refresh token, try to refresh
        if let _ = refreshToken {
            return try await refresh()
        }
        
        // No token and no refresh token - user needs to authenticate
        throw NSError(
            domain: "SpotifyAuth",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Spotify authentication required. Please connect your Spotify account."]
        )
    }
    
    // MARK: - Public API for RockList
    
    /// Gets a valid access token, refreshing if needed
    func getValidAccessToken() async throws -> String {
        return try await refreshAccessTokenIfNeeded()
    }
    
    /// Starts authorization flow (returns URL for ASWebAuthenticationSession)
    func authorizeWithSpotify() async throws {
        // This method is called to initiate auth - the actual URL is returned by startAuthorization()
        // The caller should use startAuthorization() to get the URL and present it
    }
    
    /// Handles the redirect URL from Spotify OAuth
    func handleRedirect(_ url: URL) async throws {
        await handleRedirectURL(url)
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
        save(t)
        return t.access_token
    }

    private func tokenRequest(_ body: [String : String]) async throws -> SpotifyTokens {
        guard let url = URL(string: tokenURL) else {
            throw NSError(domain: "SpotifyAuth", code: -1)
        }

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

    private func save(_ t: SpotifyTokens) {
        accessToken = t.access_token
        refreshToken = t.refresh_token ?? refreshToken

        let expiry = Date().addingTimeInterval(Double(t.expires_in))
        expirationDate = expiry

        SpotifyTokenStore.saveTokens(t, expiry: expiry)
    }
}
