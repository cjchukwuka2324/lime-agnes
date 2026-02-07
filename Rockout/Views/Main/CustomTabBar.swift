import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @ObservedObject private var tabBarState = TabBarState.shared
    
    var body: some View {
        HStack(spacing: 0) {
            TabBarButton(
                icon: "house.fill",
                title: "GreenRoom",
                isSelected: selectedTab == 0
            ) {
                selectedTab = 0
            }
            
            TabBarButton(
                icon: "sparkles.magnifyingglass",
                title: "Recall",
                isSelected: selectedTab == 1
            ) {
                selectedTab = 1
            }
            
            TabBarButton(
                icon: "slider.horizontal.3",
                title: "StudioSessions",
                isSelected: selectedTab == 2
            ) {
                selectedTab = 2
            }
            
            TabBarButton(
                icon: "globe",
                title: "Discoveries",
                isSelected: selectedTab == 3
            ) {
                selectedTab = 3
            }
            
            TabBarButton(
                icon: "person.crop.circle",
                title: "Profile",
                isSelected: selectedTab == 4
            ) {
                selectedTab = 4
            }
        }
        .frame(height: 50)
        .background(Color.black)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5),
            alignment: .top
        )
        .offset(y: tabBarState.isCollapsed ? 100 : 0)
        .opacity(tabBarState.isCollapsed ? 0 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: tabBarState.isCollapsed)
    }
}

private struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                
                Text(title)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

