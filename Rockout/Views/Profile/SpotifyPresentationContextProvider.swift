import UIKit
import AuthenticationServices

class SpotifyPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // This function is already called on the main thread by ASWebAuthenticationSession
        // Do not use DispatchQueue.main.sync as it can cause deadlock
        
        // Try to get the active window scene
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        
        // Prefer foreground active scene
        if let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) {
            if let keyWindow = activeScene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
            if let firstWindow = activeScene.windows.first {
                return firstWindow
            }
        }
        
        // Fallback to any foreground scene
        if let anyScene = scenes.first(where: { 
            $0.activationState == .foregroundInactive || 
            $0.activationState == .foregroundActive 
        }) {
            if let window = anyScene.windows.first {
                return window
            }
        }
        
        // Last resort - any scene, any window
        if let anyScene = scenes.first, let window = anyScene.windows.first {
            return window
        }
        
        // Should never happen, but provide a fallback
        return UIWindow(frame: UIScreen.main.bounds)
    }
}

