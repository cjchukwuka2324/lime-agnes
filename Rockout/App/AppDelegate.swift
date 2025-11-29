import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("🚀 App launched")
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        print("🔗 AppDelegate received URL: \(url.absoluteString)")
        print("   Scheme: \(url.scheme ?? "nil"), Host: \(url.host ?? "nil"), Path: \(url.path)")
        
        guard url.scheme == "rockout" else {
            print("⚠️ Unknown URL scheme: \(url.scheme ?? "nil")")
            return false
        }
        
        // Handle share links:
        //   rockout://share/{token}       (legacy)
        //   rockout://view/{token}        (view-only)
        //   rockout://collaborate/{token} (collaboration)
        if let host = url.host, ["share", "view", "collaborate"].contains(host) {
            var path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            path = path.replacingOccurrences(of: " ", with: "")
            path = path.replacingOccurrences(of: "\n", with: "")
            path = path.replacingOccurrences(of: "\t", with: "")
            
            // Also check if token is in the host or path components
            let components = path.components(separatedBy: "/").filter { !$0.isEmpty }
            let token = components.first ?? path
            
            let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !cleanToken.isEmpty {
                print("📎 AppDelegate handling share link (\(host)), token: \(cleanToken)")
                Task { @MainActor in
                    SharedAlbumHandler.shared.handleShareToken(cleanToken)
                }
                return true
            } else {
                print("⚠️ AppDelegate: Share link missing token. Host: '\(host)', Path: '\(url.path)'")
            }
        }
        
        // Handle Spotify OAuth: rockout://auth
        if url.host == "auth" {
            Task {
                do {
                    try await SpotifyAuthService.shared.handleRedirectURL(url)
                    print("✅ Spotify OAuth successful")
                } catch {
                    print("❌ Failed to handle Spotify redirect: \(error.localizedDescription)")
                }
            }
            return true
        }
        
        return false
    }
}

