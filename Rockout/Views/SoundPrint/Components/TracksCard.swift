//
//  TracksCard.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/17/25.
//

import SwiftUI

struct TracksCard: View {
    let tracks: [SpotifyTrack]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top Tracks")
                .font(.headline)

            ForEach(Array(tracks.prefix(5)), id: \.name) { track in
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.subheadline)
                        .bold()

                    Text(track.artists.map { $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
