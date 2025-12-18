import SwiftUI
import UIKit
import ImageIO

struct GifImage: UIViewRepresentable {
    let name: String
    let bundle: Bundle?
    
    init(_ name: String, bundle: Bundle? = nil) {
        self.name = name
        self.bundle = bundle
    }
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        
        // Try bundle first
        if let url = (bundle ?? .main).url(forResource: name, withExtension: nil) ?? 
                     (bundle ?? .main).url(forResource: name, withExtension: "gif") ?? 
                     (bundle ?? .main).url(forResource: name, withExtension: "GIF") {
            imageView.animateGif(from: url)
        } else if let path = Bundle.main.path(forResource: name, ofType: nil) ?? 
                     Bundle.main.path(forResource: name, ofType: "gif") ?? 
                     Bundle.main.path(forResource: name, ofType: "GIF") {
            imageView.animateGif(from: URL(fileURLWithPath: path))
        }
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        // No updates needed
    }
}

extension UIImageView {
    func animateGif(from url: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return
        }
        
        let count = CGImageSourceGetCount(imageSource)
        var images: [UIImage] = []
        var duration: Double = 0
        
        for i in 0..<count {
            if let cgImage = CGImageSourceCreateImageAtIndex(imageSource, i, nil) {
                images.append(UIImage(cgImage: cgImage))
                
                if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil) as? [String: Any],
                   let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any],
                   let delayTime = gifProperties[kCGImagePropertyGIFDelayTime as String] as? Double {
                    duration += delayTime
                }
            }
        }
        
        if images.count > 1 {
            self.animationImages = images
            self.animationDuration = duration
            self.animationRepeatCount = 0
            self.image = images.first
            self.startAnimating()
        } else {
            self.image = UIImage(cgImage: image)
        }
    }
}

