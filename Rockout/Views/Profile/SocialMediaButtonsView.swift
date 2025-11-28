import SwiftUI

struct SocialMediaButtonsView: View {
    let instagramHandle: String?
    let twitterHandle: String?
    let tiktokHandle: String?
    let onEdit: (SocialMediaPlatform) -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            socialMediaButton(
                platform: .instagram,
                handle: instagramHandle,
                onTap: {
                    if let handle = instagramHandle, !handle.isEmpty {
                        openSocialMediaApp(platform: .instagram, handle: handle)
                    } else {
                        onEdit(.instagram)
                    }
                },
                onLongPress: {
                    onEdit(.instagram)
                }
            )
            
            socialMediaButton(
                platform: .twitter,
                handle: twitterHandle,
                onTap: {
                    if let handle = twitterHandle, !handle.isEmpty {
                        openSocialMediaApp(platform: .twitter, handle: handle)
                    } else {
                        onEdit(.twitter)
                    }
                },
                onLongPress: {
                    onEdit(.twitter)
                }
            )
            
            socialMediaButton(
                platform: .tiktok,
                handle: tiktokHandle,
                onTap: {
                    if let handle = tiktokHandle, !handle.isEmpty {
                        openSocialMediaApp(platform: .tiktok, handle: handle)
                    } else {
                        onEdit(.tiktok)
                    }
                },
                onLongPress: {
                    onEdit(.tiktok)
                }
            )
        }
        .padding(.horizontal, 20)
    }
    
    private func socialMediaButton(platform: SocialMediaPlatform, handle: String?, onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) -> some View {
        let hasHandle = handle != nil && !handle!.isEmpty
        let cleanHandle = handle?.replacingOccurrences(of: "@", with: "") ?? ""
        
        return Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: platform.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(platform.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if hasHandle {
                        Text("@\(cleanHandle)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("Add")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(hasHandle ? platform.displayColor : Color(white: 0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        hasHandle ? platform.displayColor.opacity(0.5) : Color.white.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                onLongPress()
            } label: {
                Label("Edit \(platform.name)", systemImage: "pencil")
            }
        }
    }
    
    private func openSocialMediaApp(platform: SocialMediaPlatform, handle: String) {
        // Try to open in app first
        if let appURL = platform.appURL(for: handle),
           UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = platform.url(for: handle) {
            // Fallback to web
            UIApplication.shared.open(webURL)
        }
    }
}

