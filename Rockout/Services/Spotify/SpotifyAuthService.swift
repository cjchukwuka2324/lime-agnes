import Foundation
import Combine

@MainActor
final class SpotifyAuthService: ObservableObject {

    static let shared = SpotifyAuthService()

    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var expirationDate: Date?

    private let clientID = "13aa07c310bb445d82fc8035ee426d0c"
    private let redirectURI = "rockout://auth"
    private let tokenURL = "https://accounts.spotify.com/api/token"
    private let scopes = "user-read-email user-read-private user-top-read"

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
        if let e = expirationDate, e > Date() {
            return accessToken ?? ""
        }
        return try await refresh()
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
