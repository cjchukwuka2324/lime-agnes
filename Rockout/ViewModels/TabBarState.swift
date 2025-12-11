import SwiftUI
import Combine

class TabBarState: ObservableObject {
    @Published var isCollapsed: Bool = false
    
    static let shared = TabBarState()
    
    private init() {}
    
    func collapse() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isCollapsed = true
        }
    }
    
    func expand() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isCollapsed = false
        }
    }
    
    func toggle() {
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }
}

