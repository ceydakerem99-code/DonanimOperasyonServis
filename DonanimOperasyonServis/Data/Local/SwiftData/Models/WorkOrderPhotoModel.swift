import Foundation
import SwiftData

/// SwiftData persistence model for `WorkOrderPhoto`. Only metadata
/// (id, category, storage locator) is stored here — actual image
/// bytes are handled by a separate storage subsystem introduced in
/// a later phase.
@Model
final class WorkOrderPhotoModel {

    @Attribute(.unique) var id: String

    var workOrder: WorkOrderModel?
    var workOrderId: String

    var categoryRaw: String
    var storagePath: String?
    var capturedByUserId: String
    var capturedAt: Date

    init(
        id: String,
        workOrderId: String,
        categoryRaw: String,
        storagePath: String?,
        capturedByUserId: String,
        capturedAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.categoryRaw = categoryRaw
        self.storagePath = storagePath
        self.capturedByUserId = capturedByUserId
        self.capturedAt = capturedAt
    }
}

extension WorkOrderPhotoModel {

    convenience init(domain: WorkOrderPhoto) {
        self.init(
            id: domain.id,
            workOrderId: domain.workOrderId.rawValue,
            categoryRaw: domain.category.rawValue,
            storagePath: domain.storagePath,
            capturedByUserId: domain.capturedByUserId.rawValue,
            capturedAt: domain.capturedAt
        )
    }

    func apply(domain: WorkOrderPhoto) {
        self.workOrderId = domain.workOrderId.rawValue
        self.categoryRaw = domain.category.rawValue
        self.storagePath = domain.storagePath
        self.capturedByUserId = domain.capturedByUserId.rawValue
        self.capturedAt = domain.capturedAt
    }

    func toDomain() -> WorkOrderPhoto? {
        guard let category = PhotoCategory(rawValue: categoryRaw) else { return nil }
        return WorkOrderPhoto(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            category: category,
            storagePath: storagePath,
            capturedByUserId: UserID(capturedByUserId),
            capturedAt: capturedAt
        )
    }
}
