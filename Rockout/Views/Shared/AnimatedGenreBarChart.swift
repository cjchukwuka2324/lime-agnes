//
//  AnimatedGenreBarChart.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/18/25.
//

import SwiftUI

struct AnimatedGenreBarChart: View {
    let genreCounts: [(String, Int, Double)]
    @State private var animate = false

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(genreCounts.enumerated()), id: \.offset) { idx, item in
                HStack {
                    Text(item.0)
                        .foregroundColor(.white)
                        .font(.caption)
                        .frame(width: 90, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: animate ? geo.size.width * CGFloat(item.2) : 0)
                                .animation(.easeOut.delay(0.05 * Double(idx)), value: animate)
                        }
                    }
                    .frame(height: 14)

                    Text("\(Int(item.2 * 100))%")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 40)
                }
                .frame(height: 20)
            }
        }
        .onAppear { animate = true }
    }
}
