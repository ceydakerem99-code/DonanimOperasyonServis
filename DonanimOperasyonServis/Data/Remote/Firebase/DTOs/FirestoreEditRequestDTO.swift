import Foundation

/// Firestore DTO for the `editRequests` collection.
struct FirestoreEditRequestDTO: Codable, Hashable, Sendable {
    let id: String
    let workOrderId: String
    let requestedByUserId: String
    let createdAt: Date
    let reason: String
    /// Name of the whitelisted field on the target `WorkOrder`
    /// (see `EditableWorkOrderField.rawValue`).
    let field: String
    let currentValue: String
    let requestedValue: String
    let status: String
    let reviewedByUserId: String?
    let reviewedAt: Date?
    let decisionNote: String?
}

extension FirestoreEditRequestDTO {

    init(domain: EditRequest) {
        self.id = domain.id.rawValue
        self.workOrderId = domain.workOrderId.rawValue
        self.requestedByUserId = domain.requestedByUserId.rawValue
        self.createdAt = domain.createdAt
        self.reason = domain.reason
        self.field = domain.field
        self.currentValue = domain.currentValue
        self.requestedValue = domain.requestedValue
        self.status = domain.status.rawValue
        self.reviewedByUserId = domain.reviewedByUserId?.rawValue
        self.reviewedAt = domain.reviewedAt
        self.decisionNote = domain.decisionNote
    }

    func toDomain() -> EditRequest? {
        guard let resolvedStatus = EditRequestStatus(rawValue: status) else { return nil }
        return EditRequest(
            id: EditRequestID(id),
            workOrderId: WorkOrderID(workOrderId),
            requestedByUserId: UserID(requestedByUserId),
            createdAt: createdAt,
            reason: reason,
            field: field,
            currentValue: currentValue,
            requestedValue: requestedValue,
            status: resolvedStatus,
            reviewedByUserId: reviewedByUserId.map(UserID.init),
            reviewedAt: reviewedAt,
            decisionNote: decisionNote
        )
    }
}
