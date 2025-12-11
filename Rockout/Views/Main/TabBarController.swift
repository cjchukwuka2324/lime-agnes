import SwiftUI
import UIKit

struct TabBarUpdater: View {
    @ObservedObject var tabBarState: TabBarState
    
    var body: some View {
        Color.clear
            .onAppear {
                updateTabBarAppearance(collapsed: tabBarState.isCollapsed)
            }
            .onChange(of: tabBarState.isCollapsed) { _, isCollapsed in
                updateTabBarAppearance(collapsed: isCollapsed)
            }
            .background(
                TabBarAccessor { tabBar in
                    updateTabBarDirectly(tabBar, collapsed: tabBarState.isCollapsed)
                }
            )
    }
    
    private func updateTabBarAppearance(collapsed: Bool) {
        DispatchQueue.main.async {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.black
            appearance.shadowColor = .clear
            appearance.backgroundEffect = nil
            
            if collapsed {
                // Hide labels by making font size 0 and moving off screen
                appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: UIColor.clear,
                    .font: UIFont.systemFont(ofSize: 0.01)
                ]
                appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: UIColor.clear,
                    .font: UIFont.systemFont(ofSize: 0.01)
                ]
                appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 200)
                appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 200)
            } else {
                // Show labels
                appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: UIColor.white.withAlphaComponent(0.6)
                ]
                appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: UIColor.white
                ]
                appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = .zero
                appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = .zero
            }
            
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
            
            UITabBar.appearance().standardAppearance = appearance
            if #available(iOS 15.0, *) {
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
            
            // Force update
            updateAllTabBars()
        }
    }
    
    private func updateTabBarDirectly(_ tabBar: UITabBar, collapsed: Bool) {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.black
        appearance.shadowColor = .clear
        appearance.backgroundEffect = nil
        
        if collapsed {
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.clear,
                .font: UIFont.systemFont(ofSize: 0.01)
            ]
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.clear,
                .font: UIFont.systemFont(ofSize: 0.01)
            ]
            appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 200)
            appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 200)
        } else {
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.white.withAlphaComponent(0.6)
            ]
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.white
            ]
            appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = .zero
            appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = .zero
        }
        
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.6)
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.white
        
        tabBar.standardAppearance = appearance
        if #available(iOS 15.0, *) {
            tabBar.scrollEdgeAppearance = appearance
        }
        tabBar.setNeedsLayout()
        tabBar.layoutIfNeeded()
    }
    
    private func updateAllTabBars() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        
        func findTabBars(in view: UIView) {
            if let tabBar = view as? UITabBar {
                let appearance = tabBar.standardAppearance
                tabBar.standardAppearance = appearance
                if #available(iOS 15.0, *) {
                    tabBar.scrollEdgeAppearance = appearance
                }
                tabBar.setNeedsLayout()
                tabBar.layoutIfNeeded()
            }
            for subview in view.subviews {
                findTabBars(in: subview)
            }
        }
        
        findTabBars(in: window)
    }
}

struct TabBarAccessor: UIViewControllerRepresentable {
    var callback: (UITabBar) -> Void
    
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let tabBarController = uiViewController.tabBarController {
            callback(tabBarController.tabBar)
        } else {
            DispatchQueue.main.async {
                if let tabBarController = uiViewController.tabBarController {
                    callback(tabBarController.tabBar)
                }
            }
        }
    }
}

