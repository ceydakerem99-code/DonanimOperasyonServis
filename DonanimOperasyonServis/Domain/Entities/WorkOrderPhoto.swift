import Foundation

/// Metadata describing a photo attached to a work order. The binary
/// content itself lives in a separate storage layer (added in
/// later phases) — this entity intentionally holds only the URL /
/// path that identifies where the bytes can be fetched.
///
/// `category` is what `PhotoRequirements` inspects to decide whether
/// the work order has met its photo evidence requirements.
struct WorkOrderPhoto: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let workOrderId: WorkOrderID
    let category: PhotoCategory
    /// Storage locator (Firebase Storage path or local file URL,
    /// depending on where the photo currently lives). May be `nil`
    /// while a locally-captured photo is queued for upload.
    var storagePath: String?
    let capturedByUserId: UserID
    let capturedAt: Date

    init(
        id: String,
        workOrderId: WorkOrderID,
        category: PhotoCategory,
        storagePath: String? = nil,
        capturedByUserId: UserID,
        capturedAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.category = category
        self.storagePath = storagePath
        self.capturedByUserId = capturedByUserId
        self.capturedAt = capturedAt
    }
}
