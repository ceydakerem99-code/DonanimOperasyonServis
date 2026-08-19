import Foundation

/// Firestore DTO for the `workOrderPhotos` collection.
///
/// Only metadata (id, category, capture info, storage locator) is
/// persisted here. The actual image bytes live in Firebase Storage
/// under `workOrders/{workOrderId}/photos/{photoId}` — see
/// `FirebaseStoragePath`.
struct FirestoreWorkOrderPhotoDTO: Codable, Hashable, Sendable {
    let id: String
    let workOrderId: String
    let category: String
    let storagePath: String?
    let capturedByUserId: String
    let capturedAt: Date
}

extension FirestoreWorkOrderPhotoDTO {

    init(domain: WorkOrderPhoto) {
        self.id = domain.id
        self.workOrderId = domain.workOrderId.rawValue
        self.category = domain.category.rawValue
        self.storagePath = domain.storagePath
        self.capturedByUserId = domain.capturedByUserId.rawValue
        self.capturedAt = domain.capturedAt
    }

    func toDomain() -> WorkOrderPhoto? {
        guard let resolvedCategory = PhotoCategory(rawValue: category) else { return nil }
        return WorkOrderPhoto(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            category: resolvedCategory,
            storagePath: storagePath,
            capturedByUserId: UserID(capturedByUserId),
            capturedAt: capturedAt
        )
    }
}
