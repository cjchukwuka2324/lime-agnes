//
//  AvatarView.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/17/25.
//

import SwiftUI

struct AvatarView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { img in
                    img.resizable()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
