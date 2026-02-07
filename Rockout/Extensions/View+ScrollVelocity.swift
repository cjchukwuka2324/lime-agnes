import SwiftUI

/// Preference key for tracking scroll velocity
struct ScrollVelocityPreferenceKey: PreferenceKey {
    static var defaultValue: ScrollVelocity = ScrollVelocity(offset: 0, velocity: 0, timestamp: Date())
    static func reduce(value: inout ScrollVelocity, nextValue: () -> ScrollVelocity) {
        value = nextValue()
    }
}

/// Scroll velocity data
struct ScrollVelocity: Equatable {
    let offset: CGFloat
    let velocity: CGFloat // points per second
    let timestamp: Date
    
    static func == (lhs: ScrollVelocity, rhs: ScrollVelocity) -> Bool {
        // Compare offset and velocity (ignore timestamp for equality)
        return lhs.offset == rhs.offset && lhs.velocity == rhs.velocity
    }
}

/// View that tracks scroll velocity
struct ScrollVelocityReader: View {
    @Binding var scrollVelocity: CGFloat
    @Binding var isScrolling: Bool
    
    @State private var lastOffset: CGFloat = 0
    @State private var lastTimestamp: Date = Date()
    
    private let velocityThreshold: CGFloat = 50.0 // points per second
    
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: ScrollVelocityPreferenceKey.self,
                    value: ScrollVelocity(
                        offset: -geometry.frame(in: .named("scrollView")).minY,
                        velocity: 0, // Will be calculated
                        timestamp: Date()
                    )
                )
        }
        .frame(height: 0)
        .onPreferenceChange(ScrollVelocityPreferenceKey.self) { velocity in
            let now = Date()
            let timeDelta = now.timeIntervalSince(lastTimestamp)
            
            if timeDelta > 0 {
                let offsetDelta = velocity.offset - lastOffset
                let calculatedVelocity = abs(offsetDelta / timeDelta)
                
                scrollVelocity = calculatedVelocity
                isScrolling = calculatedVelocity > velocityThreshold
            }
            
            lastOffset = velocity.offset
            lastTimestamp = now
        }
    }
}

extension View {
    /// Track scroll velocity and update binding
    func trackScrollVelocity(velocity: Binding<CGFloat>, isScrolling: Binding<Bool>) -> some View {
        self
            .coordinateSpace(name: "scrollView")
            .background(ScrollVelocityReader(scrollVelocity: velocity, isScrolling: isScrolling))
    }
}

