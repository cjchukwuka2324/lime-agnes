//
//  WelcomeView.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/17/25.
//

import SwiftUI

struct WelcomeView: View {

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {

                Text("RockOut")
                    .font(.largeTitle.bold())

                Text("Welcome to the new music experience.")
                    .font(.body)
                    .foregroundColor(.secondary)

                NavigationLink("Continue") {
                    ConnectSpotifyView()   // ⬅️ goes here
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .padding()
        }
    }
}

#Preview { WelcomeView() }
