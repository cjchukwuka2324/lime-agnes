import SwiftUI

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollViewOffsetReader: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: -geometry.frame(in: .named("scrollView")).minY
                )
        }
        .frame(height: 0)
    }
}

extension View {
    func detectScroll(collapseThreshold: CGFloat = 50) -> some View {
        self
            .coordinateSpace(name: "scrollView")
            .background(ScrollViewOffsetReader())
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                DispatchQueue.main.async {
                    if offset > collapseThreshold {
                        TabBarState.shared.collapse()
                    } else if offset < 10 {
                        TabBarState.shared.expand()
                    }
                }
            }
    }
}
