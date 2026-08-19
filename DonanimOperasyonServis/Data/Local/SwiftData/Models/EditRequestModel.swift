import Foundation
import SwiftData

/// SwiftData persistence model for `EditRequest`. Backed by an
/// inverse relationship into `WorkOrderModel.editRequests` so
/// cascade-deleting a work order also removes all its edit requests.
@Model
final class EditRequestModel {

    @Attribute(.unique) var id: String

    var workOrder: WorkOrderModel?
    var workOrderId: String

    var requestedByUserId: String
    var createdAt: Date

    var reason: String
    var field: String
    var currentValue: String
    var requestedValue: String

    var statusRaw: String
    var reviewedByUserId: String?
    var reviewedAt: Date?
    var decisionNote: String?

    init(
        id: String,
        workOrderId: String,
        requestedByUserId: String,
        createdAt: Date,
        reason: String,
        field: String,
        currentValue: String,
        requestedValue: String,
        statusRaw: String,
        reviewedByUserId: String?,
        reviewedAt: Date?,
        decisionNote: String?
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.requestedByUserId = requestedByUserId
        self.createdAt = createdAt
        self.reason = reason
        self.field = field
        self.currentValue = currentValue
        self.requestedValue = requestedValue
        self.statusRaw = statusRaw
        self.reviewedByUserId = reviewedByUserId
        self.reviewedAt = reviewedAt
        self.decisionNote = decisionNote
    }
}

extension EditRequestModel {

    convenience init(domain: EditRequest) {
        self.init(
            id: domain.id.rawValue,
            workOrderId: domain.workOrderId.rawValue,
            requestedByUserId: domain.requestedByUserId.rawValue,
            createdAt: domain.createdAt,
            reason: domain.reason,
            field: domain.field,
            currentValue: domain.currentValue,
            requestedValue: domain.requestedValue,
            statusRaw: domain.status.rawValue,
            reviewedByUserId: domain.reviewedByUserId?.rawValue,
            reviewedAt: domain.reviewedAt,
            decisionNote: domain.decisionNote
        )
    }

    func apply(domain: EditRequest) {
        self.workOrderId = domain.workOrderId.rawValue
        self.requestedByUserId = domain.requestedByUserId.rawValue
        self.createdAt = domain.createdAt
        self.reason = domain.reason
        self.field = domain.field
        self.currentValue = domain.currentValue
        self.requestedValue = domain.requestedValue
        self.statusRaw = domain.status.rawValue
        self.reviewedByUserId = domain.reviewedByUserId?.rawValue
        self.reviewedAt = domain.reviewedAt
        self.decisionNote = domain.decisionNote
    }

    func toDomain() -> EditRequest? {
        guard let status = EditRequestStatus(rawValue: statusRaw) else { return nil }
        return EditRequest(
            id: EditRequestID(id),
            workOrderId: WorkOrderID(workOrderId),
            requestedByUserId: UserID(requestedByUserId),
            createdAt: createdAt,
            reason: reason,
            field: field,
            currentValue: currentValue,
            requestedValue: requestedValue,
            status: status,
            reviewedByUserId: reviewedByUserId.map(UserID.init),
            reviewedAt: reviewedAt,
            decisionNote: decisionNote
        )
    }
}
