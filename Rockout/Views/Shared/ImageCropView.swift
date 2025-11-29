import SwiftUI
import UIKit

struct ImageCropView: View {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    @State private var cropMode: CropMode = .freeform
    @State private var aspectRatio: CGFloat = 1.0
    
    enum CropMode {
        case freeform
        case square
        case portrait
        case landscape
    }
    
    private var cropSize: CGFloat {
        UIScreen.main.bounds.width - 40
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text("Adjust Photo")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.top)
                    
                    // Crop mode selector
                    Picker("Crop Mode", selection: $cropMode) {
                        Text("Freeform").tag(CropMode.freeform)
                        Text("Square").tag(CropMode.square)
                        Text("Portrait").tag(CropMode.portrait)
                        Text("Landscape").tag(CropMode.landscape)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: cropMode) { _, newMode in
                        switch newMode {
                        case .freeform:
                            aspectRatio = 0 // No constraint
                        case .square:
                            aspectRatio = 1.0
                        case .portrait:
                            aspectRatio = 3.0 / 4.0
                        case .landscape:
                            aspectRatio = 4.0 / 3.0
                        }
                    }
                    
                    // Image crop area
                    ZStack {
                        // Background
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: cropSize, height: cropMode == .freeform ? cropSize : cropSize / aspectRatio)
                        
                        // Crop overlay
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .scaleEffect(scale)
                                .offset(offset)
                                .frame(width: cropSize, height: cropMode == .freeform ? cropSize : cropSize / aspectRatio)
                                .clipped()
                                .cornerRadius(12)
                        }
                        
                        // Crop frame
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "#1ED760"), lineWidth: 2)
                            .frame(width: cropSize, height: cropMode == .freeform ? cropSize : cropSize / aspectRatio)
                    }
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 0.5), 3.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )
                    
                    Spacer()
                    
                    // Instructions
                    VStack(spacing: 8) {
                        HStack(spacing: 16) {
                            Label("Pinch to zoom", systemImage: "arrow.up.arrow.down")
                            Label("Drag to move", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.bottom, 20)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Skip") {
                            // Don't crop, just dismiss
                            dismiss()
                        }
                        .foregroundColor(.white.opacity(0.7))
                        
                        Button("Done") {
                            cropImage()
                        }
                        .foregroundColor(Color(hex: "#1ED760"))
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }
    
    private func cropImage() {
        guard let originalImage = image else { return }
        
        let imageSize = originalImage.size
        let imageAspectRatio = imageSize.width / imageSize.height
        
        // Calculate displayed size based on crop mode
        let displayedSize: CGSize
        let cropHeight: CGFloat
        
        if cropMode == .freeform {
            // Freeform: use image's natural aspect ratio
            if imageAspectRatio > 1.0 {
                displayedSize = CGSize(width: cropSize, height: cropSize / imageAspectRatio)
            } else {
                displayedSize = CGSize(width: cropSize * imageAspectRatio, height: cropSize)
            }
            cropHeight = displayedSize.height
        } else {
            // Fixed aspect ratio
            cropHeight = cropSize / aspectRatio
            displayedSize = CGSize(width: cropSize, height: cropHeight)
        }
        
        // Calculate scale factor
        let scaleFactor = imageSize.width / displayedSize.width
        
        // Calculate crop center
        let cropCenterX = (cropSize / 2) + offset.width
        let cropCenterY = (cropHeight / 2) + offset.height
        
        // Convert to image coordinates
        let cropCenterXInImage = cropCenterX * scaleFactor
        let cropCenterYInImage = cropCenterY * scaleFactor
        
        // Calculate crop size in image coordinates
        let cropWidthInImage = (cropSize * scaleFactor) / scale
        let cropHeightInImage = (cropHeight * scaleFactor) / scale
        
        // Calculate crop rect
        let cropX = max(0, min(cropCenterXInImage - (cropWidthInImage / 2), imageSize.width - cropWidthInImage))
        let cropY = max(0, min(cropCenterYInImage - (cropHeightInImage / 2), imageSize.height - cropHeightInImage))
        
        let cropRect = CGRect(
            x: cropX,
            y: cropY,
            width: min(cropWidthInImage, imageSize.width - cropX),
            height: min(cropHeightInImage, imageSize.height - cropY)
        )
        
        // Crop the image
        guard let cgImage = originalImage.cgImage?.cropping(to: cropRect) else {
            return
        }
        
        let cropped = UIImage(cgImage: cgImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
        image = cropped
        dismiss()
    }
}
