//
//  ShareExporter.swift
//  Rockout
//
//  Created by Suino Ikhioda on 11/18/25.
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

enum ShareExporter {
    @MainActor
    static func renderImage<V: View>(_ view: V, width: CGFloat = 1080, scale: CGFloat = 3.0) async -> UIImage? {
        if #available(iOS 16.0, *) {
            let renderer = ImageRenderer(content: view.frame(width: width))
            renderer.scale = scale
            return renderer.uiImage
        } else {
            guard
                let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let window = scene.windows.first
            else { return nil }

            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            return renderer.image { ctx in
                window.layer.render(in: ctx.cgContext)
            }
        }
    }
}
