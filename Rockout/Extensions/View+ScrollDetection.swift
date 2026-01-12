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
    // New direction-aware scroll detection (for FeedView)
    func detectScroll(
        directionThreshold: CGFloat = 10,
        minOffsetToHide: CGFloat = 50
    ) -> some View {
        self.modifier(ScrollDirectionModifier(
            directionThreshold: directionThreshold,
            minOffsetToHide: minOffsetToHide
        ))
    }
    
    // Old signature for backward compatibility (does nothing, just for other views)
    func detectScroll(collapseThreshold: CGFloat) -> some View {
        self.modifier(LegacyScrollModifier())
    }
}

// Legacy modifier that does nothing (for backward compatibility)
private struct LegacyScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "scrollView")
            .background(ScrollViewOffsetReader())
    }
}

private struct ScrollDirectionModifier: ViewModifier {
    let directionThreshold: CGFloat
    let minOffsetToHide: CGFloat
    
    @State private var previousOffset: CGFloat = 0
    @State private var accumulatedDelta: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { currentOffset in
                handleScrollChange(currentOffset)
            }
    }
    
    private func handleScrollChange(_ currentOffset: CGFloat) {
        // Calculate scroll delta (positive = scrolling down, negative = scrolling up)
        let delta = currentOffset - previousOffset
        
        // Accumulate delta for hysteresis
        accumulatedDelta += delta
        
        print("🔄 Scroll: offset=\(currentOffset), delta=\(delta), accumulated=\(accumulatedDelta)")
        
        // Only trigger changes if accumulated delta exceeds threshold
        if abs(accumulatedDelta) > directionThreshold {
                DispatchQueue.main.async {
                // Scrolling DOWN and past minimum offset: HIDE bars
                if accumulatedDelta > 0 && currentOffset > minOffsetToHide {
                    print("⬇️ HIDING BARS - scrolling down")
                        TabBarState.shared.collapse()
                }
                // Scrolling UP: SHOW bars (regardless of position)
                else if accumulatedDelta < 0 {
                    print("⬆️ SHOWING BARS - scrolling up")
                        TabBarState.shared.expand()
                }
                // Reset accumulator after triggering
                accumulatedDelta = 0
            }
        }
        
        previousOffset = currentOffset
    }
}
