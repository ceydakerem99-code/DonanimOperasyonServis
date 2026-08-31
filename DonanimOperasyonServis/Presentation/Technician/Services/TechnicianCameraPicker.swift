import SwiftUI
import UIKit

/// UIKit camera capture bridge. Returns JPEG bytes to the shared
/// `addPhoto(imageData:)` path — no parallel persistence logic.
struct TechnicianCameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIImagePickerController, coordinator: Coordinator) {
        coordinator.markDismissed()
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data) -> Void
        let onCancel: () -> Void
        private var didFinish = false

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func markDismissed() {
            didFinish = true
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            guard !didFinish else { return }
            didFinish = true
            DispatchQueue.main.async { [onCancel] in
                onCancel()
            }
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard !didFinish else { return }
            didFinish = true

            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            guard let image,
                  let data = image.jpegData(compressionQuality: 0.85) ?? image.pngData()
            else {
                DispatchQueue.main.async { [onCancel] in
                    onCancel()
                }
                return
            }

            // Dismiss binding first so SwiftUI tears down presentation
            // before heavy JPEG work continues on the main actor.
            DispatchQueue.main.async { [onCapture] in
                onCapture(data)
            }
        }
    }
}
