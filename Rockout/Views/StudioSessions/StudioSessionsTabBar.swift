import SwiftUI

struct StudioSessionsTabBar: View {
    typealias AlbumTab = StudioSessionsView.AlbumTab
    
    let tabs: [AlbumTab]
    @Binding var selectedTab: AlbumTab
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(tabs, id: \.self) { tab in
                        StudioTabButton(
                            title: tab.rawValue,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab = tab
                            }
                        }
                        .id(tab)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onChange(of: selectedTab) { _, newTab in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    proxy.scrollTo(newTab, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Tab Button
private struct StudioTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.15))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

