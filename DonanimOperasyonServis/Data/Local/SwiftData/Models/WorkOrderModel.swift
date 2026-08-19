import Foundation
import SwiftData

/// SwiftData persistence model for `WorkOrder`. Owns cascade-delete
/// relationships to its child records (notes, photos, GPS samples,
/// status history, signatures, edit requests) so that removing a
/// work order also removes everything anchored to it.
///
/// Foreign IDs (`createdByUserId`, `assignedTechnicianId`,
/// `customerId`) are persisted as plain strings rather than as
/// SwiftData relationships. This matches the Domain model (where
/// those are typed IDs, not embedded objects) and keeps the local
/// schema close to how the remote schema (Firestore in a later
/// phase) will store the same references.
///
/// `ScheduledTimeRange` is flattened into a nullable `(scheduledStart,
/// scheduledEnd)` pair. `PauseReason` is stored as its raw string.
@Model
final class WorkOrderModel {

    @Attribute(.unique) var id: String
    var workOrderNumber: String

    var createdByUserId: String
    var assignedTechnicianId: String
    var customerId: String

    var workTypeRaw: String
    var deviceCategoryRaw: String
    var deviceBrand: String
    var deviceModel: String
    var serialNumber: String
    var issueDescription: String?

    var priorityRaw: String

    var scheduledDate: Date
    var scheduledStart: Date?
    var scheduledEnd: Date?

    var statusRaw: String
    var currentPauseReasonRaw: String?

    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \WorkOrderNoteModel.workOrder)
    var notes: [WorkOrderNoteModel] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkOrderStatusHistoryModel.workOrder)
    var statusHistory: [WorkOrderStatusHistoryModel] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkOrderPhotoModel.workOrder)
    var photos: [WorkOrderPhotoModel] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkOrderLocationModel.workOrder)
    var locations: [WorkOrderLocationModel] = []

    @Relationship(deleteRule: .cascade, inverse: \SignatureModel.workOrder)
    var signatures: [SignatureModel] = []

    @Relationship(deleteRule: .cascade, inverse: \EditRequestModel.workOrder)
    var editRequests: [EditRequestModel] = []

    init(
        id: String,
        workOrderNumber: String,
        createdByUserId: String,
        assignedTechnicianId: String,
        customerId: String,
        workTypeRaw: String,
        deviceCategoryRaw: String,
        deviceBrand: String,
        deviceModel: String,
        serialNumber: String,
        issueDescription: String?,
        priorityRaw: String,
        scheduledDate: Date,
        scheduledStart: Date?,
        scheduledEnd: Date?,
        statusRaw: String,
        currentPauseReasonRaw: String?,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.workOrderNumber = workOrderNumber
        self.createdByUserId = createdByUserId
        self.assignedTechnicianId = assignedTechnicianId
        self.customerId = customerId
        self.workTypeRaw = workTypeRaw
        self.deviceCategoryRaw = deviceCategoryRaw
        self.deviceBrand = deviceBrand
        self.deviceModel = deviceModel
        self.serialNumber = serialNumber
        self.issueDescription = issueDescription
        self.priorityRaw = priorityRaw
        self.scheduledDate = scheduledDate
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.statusRaw = statusRaw
        self.currentPauseReasonRaw = currentPauseReasonRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

// MARK: - Domain ↔ Model mapping

extension WorkOrderModel {

    convenience init(domain: WorkOrder) {
        self.init(
            id: domain.id.rawValue,
            workOrderNumber: domain.workOrderNumber,
            createdByUserId: domain.createdByUserId.rawValue,
            assignedTechnicianId: domain.assignedTechnicianId.rawValue,
            customerId: domain.customerId.rawValue,
            workTypeRaw: domain.workType.rawValue,
            deviceCategoryRaw: domain.deviceCategory.rawValue,
            deviceBrand: domain.deviceBrand,
            deviceModel: domain.deviceModel,
            serialNumber: domain.serialNumber,
            issueDescription: domain.issueDescription,
            priorityRaw: domain.priority.rawValue,
            scheduledDate: domain.scheduledDate,
            scheduledStart: domain.scheduledTimeRange?.start,
            scheduledEnd: domain.scheduledTimeRange?.end,
            statusRaw: domain.status.rawValue,
            currentPauseReasonRaw: domain.currentPauseReason?.rawValue,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt,
            completedAt: domain.completedAt
        )
    }

    func apply(domain: WorkOrder) {
        self.workOrderNumber = domain.workOrderNumber
        self.createdByUserId = domain.createdByUserId.rawValue
        self.assignedTechnicianId = domain.assignedTechnicianId.rawValue
        self.customerId = domain.customerId.rawValue
        self.workTypeRaw = domain.workType.rawValue
        self.deviceCategoryRaw = domain.deviceCategory.rawValue
        self.deviceBrand = domain.deviceBrand
        self.deviceModel = domain.deviceModel
        self.serialNumber = domain.serialNumber
        self.issueDescription = domain.issueDescription
        self.priorityRaw = domain.priority.rawValue
        self.scheduledDate = domain.scheduledDate
        self.scheduledStart = domain.scheduledTimeRange?.start
        self.scheduledEnd = domain.scheduledTimeRange?.end
        self.statusRaw = domain.status.rawValue
        self.currentPauseReasonRaw = domain.currentPauseReason?.rawValue
        self.createdAt = domain.createdAt
        self.updatedAt = domain.updatedAt
        self.completedAt = domain.completedAt
    }

    /// Reconstructs the Domain value. Returns `nil` when any of the
    /// persisted enum raw values fails to decode (i.e. the row is
    /// corrupted).
    func toDomain() -> WorkOrder? {
        guard
            let workType = WorkType(rawValue: workTypeRaw),
            let deviceCategory = DeviceCategory(rawValue: deviceCategoryRaw),
            let priority = WorkOrderPriority(rawValue: priorityRaw),
            let status = WorkOrderStatus(rawValue: statusRaw)
        else { return nil }

        let pauseReason: PauseReason?
        if let raw = currentPauseReasonRaw {
            guard let decoded = PauseReason(rawValue: raw) else { return nil }
            pauseReason = decoded
        } else {
            pauseReason = nil
        }

        let timeRange: ScheduledTimeRange?
        if let start = scheduledStart, let end = scheduledEnd {
            timeRange = ScheduledTimeRange(uncheckedStart: start, end: end)
        } else {
            timeRange = nil
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
            scheduledTimeRange: timeRange,
            status: status,
            currentPauseReason: pauseReason,
            createdAt: createdAt,
            updatedAt: updatedAt,
            completedAt: completedAt
        )
    }
}
