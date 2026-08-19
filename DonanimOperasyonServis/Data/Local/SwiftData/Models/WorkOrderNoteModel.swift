import Foundation
import SwiftData

/// SwiftData persistence model for `WorkOrderNote`.
@Model
final class WorkOrderNoteModel {

    @Attribute(.unique) var id: String

    /// Inverse of `WorkOrderModel.notes`. Optional because SwiftData
    /// creates the row before the relationship is assigned; the
    /// repository layer guarantees the relationship is set before
    /// `save()`.
    var workOrder: WorkOrderModel?
    /// Foreign-key mirror of `workOrder?.id`, kept for predicate
    /// filtering (SwiftData `#Predicate` cannot follow optional
    /// relationships in every case).
    var workOrderId: String

    var authorUserId: String
    var text: String
    var createdAt: Date

    init(
        id: String,
        workOrderId: String,
        authorUserId: String,
        text: String,
        createdAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.authorUserId = authorUserId
        self.text = text
        self.createdAt = createdAt
    }
}

extension WorkOrderNoteModel {

    convenience init(domain: WorkOrderNote) {
        self.init(
            id: domain.id,
            workOrderId: domain.workOrderId.rawValue,
            authorUserId: domain.authorUserId.rawValue,
            text: domain.text,
            createdAt: domain.createdAt
        )
    }

    func apply(domain: WorkOrderNote) {
        self.workOrderId = domain.workOrderId.rawValue
        self.authorUserId = domain.authorUserId.rawValue
        self.text = domain.text
        self.createdAt = domain.createdAt
    }

    func toDomain() -> WorkOrderNote {
        WorkOrderNote(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            authorUserId: UserID(authorUserId),
            text: text,
            createdAt: createdAt
        )
    }
}
