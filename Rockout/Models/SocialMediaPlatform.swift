import SwiftUI

enum SocialMediaPlatform {
    case instagram
    case twitter
    case tiktok
    
    var name: String {
        switch self {
        case .instagram: return "Instagram"
        case .twitter: return "X"
        case .tiktok: return "TikTok"
        }
    }
    
    var iconName: String {
        switch self {
        case .instagram: return "instagram-icon"
        case .twitter: return "twitter-icon"
        case .tiktok: return "tiktok-icon"
        }
    }
    
    var color: Color {
        switch self {
        case .instagram: return Color(red: 225/255.0, green: 48/255.0, blue: 108/255.0) // Instagram #E1306C
        case .twitter: return Color.black // X black #000000
        case .tiktok: return Color.black // TikTok black #000000
        }
    }
    
    var displayColor: Color {
        switch self {
        case .instagram: return Color(red: 225/255.0, green: 48/255.0, blue: 108/255.0) // Instagram #E1306C (fallback)
        case .twitter: return Color.black // X black #000000
        case .tiktok: return Color.black // TikTok black #000000
        }
    }
    
    func backgroundFill(hasHandle: Bool) -> AnyShapeStyle {
        if hasHandle {
            switch self {
            case .instagram:
                return AnyShapeStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 245/255, green: 133/255, blue: 41/255),
                            Color(red: 221/255, green: 42/255,  blue: 123/255),
                            Color(red: 129/255, green: 52/255,  blue: 175/255),
                            Color(red: 81/255,  green: 91/255,  blue: 212/255)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .twitter, .tiktok:
                return AnyShapeStyle(Color.black)
            }
        } else {
            return AnyShapeStyle(Color(white: 0.15))
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

