import Foundation
import SwiftUI

@MainActor
class SharedAlbumHandler: ObservableObject {
    static let shared = SharedAlbumHandler()
    
    @Published var pendingShareToken: String?
    @Published var shouldShowAcceptSheet = false
    
    private let shareService = ShareService.shared
    
    private init() {}
    
    func handleShareToken(_ token: String) {
        // Clean the token one more time to ensure no whitespace
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
        
        guard !cleanToken.isEmpty else {
            print("⚠️ Empty token after cleaning. Original: '\(token)'")
            return
        }
        
        print("📎 Handling share token: \(cleanToken)")
        pendingShareToken = cleanToken
        shouldShowAcceptSheet = true
    }
}

