//
//  ArtistCarousel.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/17/25.
//

import SwiftUI

struct ArtistCarousel: View {
    let artists: [SpotifyArtist]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(artists.prefix(10)), id: \.name) { artist in
                    VStack(spacing: 6) {
                        AsyncImage(url: URL(string: artist.images?.first?.url ?? "")) { img in
                            img.resizable()
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())

                        Text(artist.name)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

