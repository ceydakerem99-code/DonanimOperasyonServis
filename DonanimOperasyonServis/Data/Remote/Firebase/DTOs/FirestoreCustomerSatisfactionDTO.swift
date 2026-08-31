import Foundation

/// Firestore DTO for the `customerSatisfactions` collection.
struct FirestoreCustomerSatisfactionDTO: Codable, Hashable, Sendable {
    let id: String
    let workOrderId: String
    let customerId: String
    let status: String
    let rating: Int?
    let comment: String?
    let createdAt: Date
    let updatedAt: Date
    let submittedAt: Date?
}

extension FirestoreCustomerSatisfactionDTO {

    init(domain: CustomerSatisfaction) {
        self.id = domain.id.rawValue
        self.workOrderId = domain.workOrderId.rawValue
        self.customerId = domain.customerId.rawValue
        self.status = domain.status.rawValue
        self.rating = domain.rating?.rawValue
        self.comment = domain.comment
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
        self.submittedAt = domain.submittedAt
    }

    func toDomain() -> CustomerSatisfaction? {
        guard let resolvedStatus = CustomerSatisfactionStatus(rawValue: status) else { return nil }

        let resolvedRating: CustomerSatisfactionRating?
        if let rating {
            guard let decoded = CustomerSatisfactionRating(rawValue: rating) else { return nil }
            resolvedRating = decoded
        } else {
            resolvedRating = nil
        }

        return CustomerSatisfaction(
            id: CustomerSatisfactionID(id),
            workOrderId: WorkOrderID(workOrderId),
            customerId: CustomerID(customerId),
            status: resolvedStatus,
            rating: resolvedRating,
            comment: comment,
            createdAt: createdAt,
            updatedAt: updatedAt,
            submittedAt: submittedAt
        )
    }
}
