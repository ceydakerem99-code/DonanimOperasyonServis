import Foundation

/// Firestore DTO for the `workOrders` collection.
///
/// - `ScheduledTimeRange` is flattened to a nullable pair
///   (`scheduledStart`, `scheduledEnd`); both are either present
///   together or both `nil`.
/// - All enums are persisted as their raw string.
/// - Foreign IDs (creator, technician, customer) are stored as
///   plain strings — Firestore has no explicit "reference" type in
///   our flat schema.
struct FirestoreWorkOrderDTO: Codable, Hashable, Sendable {
    let id: String
    let workOrderNumber: String
    let createdByUserId: String
    let assignedTechnicianId: String
    let customerId: String
    let workType: String
    let deviceCategory: String
    let deviceBrand: String
    let deviceModel: String
    let serialNumber: String
    let issueDescription: String?
    let priority: String
    let scheduledDate: Date
    let scheduledStart: Date?
    let scheduledEnd: Date?
    let status: String
    let currentPauseReason: String?
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
}

extension FirestoreWorkOrderDTO {

    init(domain: WorkOrder) {
        self.id = domain.id.rawValue
        self.workOrderNumber = domain.workOrderNumber
        self.createdByUserId = domain.createdByUserId.rawValue
        self.assignedTechnicianId = domain.assignedTechnicianId.rawValue
        self.customerId = domain.customerId.rawValue
        self.workType = domain.workType.rawValue
        self.deviceCategory = domain.deviceCategory.rawValue
        self.deviceBrand = domain.deviceBrand
        self.deviceModel = domain.deviceModel
        self.serialNumber = domain.serialNumber
        self.issueDescription = domain.issueDescription
        self.priority = domain.priority.rawValue
        self.scheduledDate = domain.scheduledDate
        self.scheduledStart = domain.scheduledTimeRange?.start
        self.scheduledEnd = domain.scheduledTimeRange?.end
        self.status = domain.status.rawValue
        self.currentPauseReason = domain.currentPauseReason?.rawValue
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
        self.completedAt = domain.completedAt
    }

    /// Reconstructs the Domain value. Returns `nil` when a persisted
    /// enum raw value cannot be decoded (i.e. the document is
    /// invalid / corrupt).
    func toDomain() -> WorkOrder? {
        guard
            let workType = WorkType(rawValue: workType),
            let deviceCategory = DeviceCategory(rawValue: deviceCategory),
            let priority = WorkOrderPriority(rawValue: priority),
            let status = WorkOrderStatus(rawValue: status)
        else { return nil }

        let pauseReason: PauseReason?
        if let raw = currentPauseReason {
            guard let decoded = PauseReason(rawValue: raw) else { return nil }
            pauseReason = decoded
        } else {
            pauseReason = nil
        }

        let range: ScheduledTimeRange?
        switch (scheduledStart, scheduledEnd) {
        case (nil, nil):
            range = nil
        case (let start?, let end?):
            guard let valid = ScheduledTimeRange(start: start, end: end) else { return nil }
            range = valid
        default:
            // Only one bound present — refuse to silently drop the range.
            return nil
        }

        return WorkOrder(
            id: WorkOrderID(id),
            workOrderNumber: workOrderNumber,
            createdByUserId: UserID(createdByUserId),
            assignedTechnicianId: UserID(assignedTechnicianId),
            customerId: CustomerID(customerId),
            workType: workType,
            deviceCategory: deviceCategory,
            deviceBrand: deviceBrand,
            deviceModel: deviceModel,
            serialNumber: serialNumber,
            issueDescription: issueDescription,
            priority: priority,
            scheduledDate: scheduledDate,
            scheduledTimeRange: range,
            status: status,
            currentPauseReason: pauseReason,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }
}
