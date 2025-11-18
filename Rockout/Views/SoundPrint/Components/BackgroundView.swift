//
//  BackgroundView.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/17/25.
//

import SwiftUI

struct BackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 20/255, green: 20/255, blue: 35/255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
