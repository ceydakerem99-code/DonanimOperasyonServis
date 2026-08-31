import AVFoundation
import UIKit

/// Live camera availability / permission helpers for technician photo capture.
/// Does not own capture UI — that stays in `TechnicianCameraPicker`.
enum TechnicianCameraAccess {
    @MainActor
    static var isHardwareAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static let unavailableMessage =
        "Bu cihazda kamera kullanılamıyor. Galeriden fotoğraf seçebilirsiniz."

    static let deniedMessage =
        "Kamera erişimi reddedildi. Ayarlar'dan izin verin veya galeriden fotoğraf seçin."
}
