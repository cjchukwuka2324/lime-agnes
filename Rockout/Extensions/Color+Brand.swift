import SwiftUI

extension Color {
    /// Electric purple accent color (#C13CFF)
    static let brandPurple = Color(hex: "#C13CFF")
    
    /// Neon blue accent color (#00C7FF)
    static let brandBlue = Color(hex: "#00C7FF")
    
    /// Accent magenta color (#FF4F9A)
    static let brandMagenta = Color(hex: "#FF4F9A")
    
    /// Brand gradient from purple to blue (top-left to bottom-right)
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brandPurple, brandBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Brand gradient reversed (blue to purple)
    static var brandGradientReversed: LinearGradient {
        LinearGradient(
            colors: [brandBlue, brandPurple],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Brand gradient with magenta included
    static var brandGradientWithMagenta: LinearGradient {
        LinearGradient(
            colors: [brandPurple, brandMagenta, brandBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Light gray color for body text (white with 0.7 opacity)
    static let brandLightGray = Color.white.opacity(0.7)
    
    /// Neon green color for onboarding and accents (#00FF88)
    static let brandNeonGreen = Color(hex: "#00FF88")
}


