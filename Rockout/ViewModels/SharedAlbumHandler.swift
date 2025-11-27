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
        shouldShowAcceptSheet = true
        pendingShareToken = token
    }
}

