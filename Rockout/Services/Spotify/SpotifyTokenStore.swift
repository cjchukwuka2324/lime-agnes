import Foundation
import Security

final class SpotifyTokenStore {

    private enum Keys {
        static let json = "rockout.spotify.tokens.json"
        static let access = "rockout.spotify.access"
        static let refresh = "rockout.spotify.refresh"
        static let expiry = "rockout.spotify.expiry"
        static let codeVerifier = "rockout.spotify.codeverifier"
    }

    // MARK: – Save string
    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(q as CFDictionary)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    // MARK: – Load string
    static func load(key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var o: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &o) == errSecSuccess,
              let d = o as? Data,
              let s = String(data: d, encoding: .utf8)
        else { return nil }
        return s
    }

    // MARK: – Delete
    @discardableResult
    static func delete(key: String) -> Bool {
        let q = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ] as [String : Any]
        let r = SecItemDelete(q as CFDictionary)
        return r == errSecSuccess || r == errSecItemNotFound
    }

    // MARK: – Token JSON I/O
    static func saveTokens(_ t: SpotifyTokens, expiry: Date) {
        if let d = try? JSONEncoder().encode(t),
           let s = String(data: d, encoding: .utf8) {
            save(key: Keys.json, value: s)
        }
        save(key: Keys.access, value: t.access_token)
        if let rt = t.refresh_token {
            save(key: Keys.refresh, value: rt)
        }
        save(key: Keys.expiry, value: String(expiry.timeIntervalSince1970))
    }

    static func loadTokens() -> (SpotifyTokens, Date)? {
        guard let j = load(key: Keys.json),
              let d = j.data(using: .utf8),
              let t = try? JSONDecoder().decode(SpotifyTokens.self, from: d)
        else { return nil }

        let expiryTime = Double(load(key: Keys.expiry) ?? "") ?? 0
        let expiry = Date(timeIntervalSince1970: expiryTime)

        return (t, expiry)
    }

    static func clear() {
        delete(key: Keys.json)
        delete(key: Keys.access)
        delete(key: Keys.refresh)
        delete(key: Keys.expiry)
    }

    // MARK: – PKCE
    static func saveVerifier(_ v: String) { save(key: Keys.codeVerifier, value: v) }
    static func loadVerifier() -> String? { load(key: Keys.codeVerifier) }
    static func clearVerifier() { delete(key: Keys.codeVerifier) }
}
