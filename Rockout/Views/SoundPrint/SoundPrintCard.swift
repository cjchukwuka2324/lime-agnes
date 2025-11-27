//
//  SoundPrintCard.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/17/25.
//

import Foundation
import SwiftUI

struct SoundPrintCard: View {
    let topArtists: [String]
    let topTracks: [String]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemPurple),
                    Color(.systemBlue)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .cornerRadius(24)
            .shadow(radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 20) {

                Text("Top Artists")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)

                ForEach(topArtists, id: \.self) { artist in
                    Text("•  \(artist)")
                        .foregroundColor(.white.opacity(0.9))
                        .font(.body)
                }

                Divider().overlay(Color.white.opacity(0.4))

                Text("Top Tracks")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.top, 4)

                ForEach(topTracks, id: \.self) { track in
                    Text("•  \(track)")
                        .foregroundColor(.white.opacity(0.9))
                        .font(.body)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 350)
    }
}
