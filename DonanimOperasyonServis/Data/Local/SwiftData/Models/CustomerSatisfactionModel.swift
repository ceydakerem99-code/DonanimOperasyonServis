import Foundation
import SwiftData

/// SwiftData persistence model for `CustomerSatisfaction`. Backed by an
/// inverse relationship into `WorkOrderModel.customerSatisfactions` so
/// cascade-deleting a work order also removes its satisfaction records.
@Model
final class CustomerSatisfactionModel {

    @Attribute(.unique) var id: String

    var workOrder: WorkOrderModel?
    var workOrderId: String
    var customerId: String

    var statusRaw: String
    var ratingRaw: Int?
    var comment: String?

    var createdAt: Date
    var updatedAt: Date
    var submittedAt: Date?

    init(
        id: String,
        workOrderId: String,
        customerId: String,
        statusRaw: String,
        ratingRaw: Int?,
        comment: String?,
        createdAt: Date,
        updatedAt: Date,
        submittedAt: Date?
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.customerId = customerId
        self.statusRaw = statusRaw
        self.ratingRaw = ratingRaw
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.submittedAt = submittedAt
    }
}

// MARK: - Domain ↔ Model mapping

extension CustomerSatisfactionModel {

    convenience init(domain: CustomerSatisfaction) {
        self.init(
            id: domain.id.rawValue,
            workOrderId: domain.workOrderId.rawValue,
            customerId: domain.customerId.rawValue,
            statusRaw: domain.status.rawValue,
            ratingRaw: domain.rating?.rawValue,
            comment: domain.comment,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            submittedAt: domain.submittedAt
        )
    }

    func apply(domain: CustomerSatisfaction) {
        self.workOrderId = domain.workOrderId.rawValue
        self.customerId = domain.customerId.rawValue
        self.statusRaw = domain.status.rawValue
        self.ratingRaw = domain.rating?.rawValue
        self.comment = domain.comment
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
        self.submittedAt = domain.submittedAt
    }

    func toDomain() -> CustomerSatisfaction? {
        guard let status = CustomerSatisfactionStatus(rawValue: statusRaw) else { return nil }

        let rating: CustomerSatisfactionRating?
        if let ratingRaw {
            guard let decoded = CustomerSatisfactionRating(rawValue: ratingRaw) else { return nil }
            rating = decoded
        } else {
            rating = nil
        }

        return CustomerSatisfaction(
            id: CustomerSatisfactionID(id),
            workOrderId: WorkOrderID(workOrderId),
            customerId: CustomerID(customerId),
            status: status,
            rating: rating,
            comment: comment,
            createdAt: createdAt,
            updatedAt: updatedAt,
            submittedAt: submittedAt
        )
    }
}
