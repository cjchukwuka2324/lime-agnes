import SwiftUI

struct PageIndicator: View {
    let currentPage: Int
    let totalPages: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.brandPurple : Color.white.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(index == currentPage ? Color.brandPurple : Color.clear, lineWidth: 2)
                    )
                    .shadow(color: index == currentPage ? Color.brandPurple.opacity(0.6) : Color.clear, radius: 4)
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
    }
}




