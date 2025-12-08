import SwiftUI

/// Manages onboarding state using @AppStorage
class OnboardingState: ObservableObject {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    
    static let shared = OnboardingState()
    
    private init() {}
    
    /// Mark onboarding as complete
    func markOnboardingComplete() {
        hasSeenOnboarding = true
    }
    
    /// Check if onboarding should be shown
    func shouldShowOnboarding() -> Bool {
        return !hasSeenOnboarding
    }
    
    /// Reset onboarding (useful for testing)
    func resetOnboarding() {
        hasSeenOnboarding = false
    }
}




