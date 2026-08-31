import Foundation

/// Loads work-order photo / signature bytes for read-only report UIs.
/// Prefers on-device cache, then Firebase Storage when synced.
struct WorkOrderMediaLoader: Sendable {
    let storage: (any FirebaseStorageDataSource)?

    init(storage: (any FirebaseStorageDataSource)? = nil) {
        self.storage = storage
    }

    func loadPhoto(_ photo: WorkOrderPhoto) async -> Data? {
        if let local = TechnicianLocalMediaStore.loadPhoto(
            workOrderId: photo.workOrderId,
            photoId: photo.id
        ), !local.isEmpty {
            return local
        }
        guard let storage,
              let path = photo.storagePath,
              !path.isEmpty,
              !PendingStoragePath.isPending(path),
              !path.hasPrefix("demo://")
        else {
            return nil
        }
        return try? await storage.download(
            from: .photo(workOrderId: photo.workOrderId, photoId: photo.id)
        )
    }

    func loadSignature(_ signature: Signature) async -> Data? {
        if let local = TechnicianLocalMediaStore.loadSignature(
            workOrderId: signature.workOrderId,
            signatureId: signature.id
        ), !local.isEmpty {
            return local
        }
        guard let storage,
              let path = signature.storagePath,
              !path.isEmpty,
              !PendingStoragePath.isPending(path),
              !path.hasPrefix("demo://")
        else {
            return nil
        }
        return try? await storage.download(
            from: .signature(workOrderId: signature.workOrderId, signatureId: signature.id)
        )
    }
}
