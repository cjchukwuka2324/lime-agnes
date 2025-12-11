import UIKit
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("🚀 App launched")
        
        // Request notification permissions
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Failed to request notification authorization: \(error.localizedDescription)")
            } else if granted {
                print("✅ Notification authorization granted")
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("⚠️ Notification authorization denied")
            }
        }
        
        return true
    }
    
    // MARK: - Push Notification Registration
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 Device token received: \(tokenString)")
        
        Task {
            await DeviceTokenService.shared.registerDeviceToken(tokenString)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // MARK: - Notification Handling
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("📬 Notification tapped: \(userInfo)")
        
        // Handle notification tap - navigate to relevant screen
        if let postId = userInfo["post_id"] as? String {
            NotificationCenter.default.post(name: .navigateToPost, object: nil, userInfo: ["post_id": postId])
        }
        
        completionHandler()
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
        
        // Handle auth callbacks: rockout://auth/callback (email confirmation) or rockout://auth (OAuth)
        // Note: Primary handling is done in RockOutApp.onOpenURL, but AppDelegate is a fallback
        if url.host == "auth" {
            // Check if this is an email confirmation link (has callback path or query params)
            if url.path.contains("callback") || url.query != nil {
                // This is likely an email confirmation or password reset link
                // Handle by restoring session directly via Supabase client
                print("🔐 AppDelegate: Handling as email confirmation/password reset link")
                Task { @MainActor in
                    do {
                        let supabase = SupabaseService.shared.client
                        let session = try await supabase.auth.session(from: url)
                        print("✅ AppDelegate: Session restored from URL for:", session.user.email ?? "nil")
                        // Post notification so AuthViewModel can pick it up
                        NotificationCenter.default.post(name: NSNotification.Name("SessionRestored"), object: nil)
                    } catch {
                        print("⚠️ AppDelegate: Could not restore session from URL:", error.localizedDescription)
                    }
                }
            } else {
                // Spotify OAuth callback
                Task {
                    do {
                        try await SpotifyAuthService.shared.handleRedirectURL(url)
                        print("✅ Spotify OAuth successful")
                    } catch {
                        print("❌ Failed to handle Spotify redirect: \(error.localizedDescription)")
                    }
                }
            }
            return true
        }
        
        // Handle password reset: rockout://password-reset
        if url.host == "password-reset" || url.path.contains("password-reset") {
            print("🔐 AppDelegate: Handling as password reset link")
            Task { @MainActor in
                do {
                    let supabase = SupabaseService.shared.client
                    let session = try await supabase.auth.session(from: url)
                    print("✅ AppDelegate: Session restored from password reset URL")
                    NotificationCenter.default.post(name: NSNotification.Name("SessionRestored"), object: nil)
                } catch {
                    print("⚠️ AppDelegate: Could not restore session from password reset URL:", error.localizedDescription)
                }
            }
            return true
        }
        
        return false
    }
}

