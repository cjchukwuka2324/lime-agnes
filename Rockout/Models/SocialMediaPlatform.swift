import SwiftUI

enum SocialMediaPlatform {
    case instagram
    case twitter
    case tiktok
    
    var name: String {
        switch self {
        case .instagram: return "Instagram"
        case .twitter: return "Twitter"
        case .tiktok: return "TikTok"
        }
    }
    
    var iconName: String {
        switch self {
        case .instagram: return "camera.fill" // Instagram camera icon
        case .twitter: return "x.circle.fill" // Twitter/X icon
        case .tiktok: return "music.note" // TikTok music note
        }
    }
    
    var color: Color {
        switch self {
        case .instagram: return Color(red: 0.8, green: 0.2, blue: 0.5) // Instagram pink
        case .twitter: return Color(red: 0.1, green: 0.6, blue: 1.0) // Twitter blue
        case .tiktok: return Color(red: 0.0, green: 0.0, blue: 0.0) // TikTok black (but we'll use a dark gray for visibility)
        }
    }
    
    var displayColor: Color {
        switch self {
        case .instagram: return Color(red: 0.8, green: 0.2, blue: 0.5)
        case .twitter: return Color(red: 0.1, green: 0.6, blue: 1.0)
        case .tiktok: return Color(white: 0.2) // Dark gray for better visibility on black background
        }
    }
    
    func url(for handle: String) -> URL? {
        let cleanHandle = handle.replacingOccurrences(of: "@", with: "")
        switch self {
        case .instagram:
            return URL(string: "https://www.instagram.com/\(cleanHandle)/")
        case .twitter:
            return URL(string: "https://twitter.com/\(cleanHandle)")
        case .tiktok:
            return URL(string: "https://www.tiktok.com/@\(cleanHandle)")
        }
    }
    
    func appURL(for handle: String) -> URL? {
        let cleanHandle = handle.replacingOccurrences(of: "@", with: "")
        switch self {
        case .instagram:
            return URL(string: "instagram://user?username=\(cleanHandle)")
        case .twitter:
            return URL(string: "twitter://user?screen_name=\(cleanHandle)")
        case .tiktok:
            return URL(string: "tiktok://user?username=\(cleanHandle)")
        }
    }
}

extension SocialMediaPlatform: Identifiable {
    var id: String {
        name
    }
}

