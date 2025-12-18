import SwiftUI
import UIKit

struct RecallTabBarIconHelper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Find the tab bar controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                return
            }
            
            // Traverse view hierarchy to find UITabBarController
            func findTabBarController(in viewController: UIViewController?) -> UITabBarController? {
                guard let vc = viewController else { return nil }
                if let tabBar = vc as? UITabBarController {
                    return tabBar
                }
                for child in vc.children {
                    if let tabBar = findTabBarController(in: child) {
                        return tabBar
                    }
                }
                return nil
            }
            
            guard let tabBarController = findTabBarController(in: window.rootViewController) else {
                return
            }
            
            // Get the Recall tab (index 1)
            guard tabBarController.tabBar.items?.count ?? 0 > 1,
                  let recallTabItem = tabBarController.tabBar.items?[1] else {
                return
            }
            
            // Create pulsing orb icon using UIKit layers (more reliable for tab bar)
            let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
            containerView.backgroundColor = .clear
            
            // Create pulsing orb layer
            let orbLayer = CAShapeLayer()
            orbLayer.frame = CGRect(x: 7, y: 7, width: 16, height: 16)
            orbLayer.path = UIBezierPath(ovalIn: orbLayer.bounds).cgPath
            orbLayer.fillColor = UIColor(hex: "#1ED760").cgColor
            
            // Add glow
            orbLayer.shadowColor = UIColor(hex: "#1ED760").cgColor
            orbLayer.shadowRadius = 4
            orbLayer.shadowOpacity = 0.6
            orbLayer.shadowOffset = .zero
            
            containerView.layer.addSublayer(orbLayer)
            
            // Add pulsing animation
            let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
            pulseAnimation.fromValue = 1.0
            pulseAnimation.toValue = 1.2
            pulseAnimation.duration = 1.5
            pulseAnimation.autoreverses = true
            pulseAnimation.repeatCount = .infinity
            pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            orbLayer.add(pulseAnimation, forKey: "pulse")
            
            // Add sparkles
            for i in 0..<3 {
                let sparkle = CAShapeLayer()
                sparkle.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
                sparkle.path = UIBezierPath(ovalIn: sparkle.bounds).cgPath
                sparkle.fillColor = UIColor.white.cgColor
                sparkle.opacity = 0.6
                
                let angle = CGFloat(i) * 2 * .pi / 3
                sparkle.position = CGPoint(
                    x: 15 + cos(angle) * 10,
                    y: 15 + sin(angle) * 10
                )
                
                containerView.layer.addSublayer(sparkle)
                
                // Animate sparkles
                let sparkleAnimation = CABasicAnimation(keyPath: "opacity")
                sparkleAnimation.fromValue = 0.3
                sparkleAnimation.toValue = 0.8
                sparkleAnimation.duration = 1.5
                sparkleAnimation.beginTime = CACurrentMediaTime() + Double(i) * 0.5
                sparkleAnimation.autoreverses = true
                sparkleAnimation.repeatCount = .infinity
                sparkleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                
                sparkle.add(sparkleAnimation, forKey: "sparkle")
            }
            
            // Render to image (static snapshot for tab bar)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30))
            let iconImage = renderer.image { context in
                containerView.layer.render(in: context.cgContext)
            }
            
            // Set the icon
            recallTabItem.image = iconImage.withRenderingMode(.alwaysOriginal)
            recallTabItem.selectedImage = iconImage.withRenderingMode(.alwaysOriginal)
        }
    }
}

// Helper view to render the pulsing orb using SwiftUI
struct RecallTabBarIconView: View {
    var body: some View {
        RecallTabBarIcon()
    }
}

extension UIView {
    func snapshot() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(bounds.size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        layer.render(in: context)
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

extension View {
    func snapshot() -> UIImage? {
        let controller = UIHostingController(rootView: self)
        let view = controller.view
        
        let targetSize = controller.view.intrinsicContentSize
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

