import SwiftUI

/// Preference key for tracking scroll offset
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// ScrollVelocityPreferenceKey and ScrollVelocityReader are defined in View+ScrollVelocity.swift
// This file only contains ScrollOffsetPreferenceKey which is used locally

