import SwiftUI
import UIKit
import AVFoundation

struct CameraPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedImages: [UIImage]
    @Binding var selectedVideo: URL?
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        
        picker.modalPresentationStyle = .fullScreen
        picker.modalPresentationCapturesStatusBarAppearance = true
        picker.view.backgroundColor = .black
        
        // Check if camera is available
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.mediaTypes = ["public.image", "public.movie"]
            picker.videoMaximumDuration = 60 // 60 seconds max
            picker.videoQuality = .typeHigh
            picker.cameraCaptureMode = .photo
            picker.cameraDevice = .rear
        } else {
            // Fallback to photo library if camera not available
            picker.sourceType = .photoLibrary
            picker.mediaTypes = ["public.image", "public.movie"]
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        
        init(_ parent: CameraPickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                // Photo captured
                if parent.selectedImages.count < 4 {
                    parent.selectedImages.append(image)
                }
            } else if let videoURL = info[.mediaURL] as? URL {
                // Video captured
                parent.selectedVideo = videoURL
            }
            
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
