import Foundation

/// A customer satisfaction response (or pending survey) for a completed
/// work order. Scoped to both the originating `WorkOrder` and the
/// responding `Customer` so satisfaction can be queried per order or
/// aggregated per customer without joining through work orders.
///
/// `rating` and `comment` are populated only after the customer submits
/// the survey (`status == .submitted`).
struct CustomerSatisfaction: Hashable, Sendable, Identifiable, Codable {
    let id: CustomerSatisfactionID
    let workOrderId: WorkOrderID
    let customerId: CustomerID

    var status: CustomerSatisfactionStatus
    var rating: CustomerSatisfactionRating?
    var comment: String?

    let createdAt: Date
    var updatedAt: Date
    var submittedAt: Date?

    init(
        id: CustomerSatisfactionID,
        workOrderId: WorkOrderID,
        customerId: CustomerID,
        status: CustomerSatisfactionStatus = .pending,
        rating: CustomerSatisfactionRating? = nil,
        comment: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        submittedAt: Date? = nil
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.customerId = customerId
        self.status = status
        self.rating = rating
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.submittedAt = submittedAt
    }
}
