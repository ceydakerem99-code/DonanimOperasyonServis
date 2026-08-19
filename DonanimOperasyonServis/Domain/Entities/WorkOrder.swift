import Foundation

/// The central operational entity: a scheduled piece of field work
/// (installation, maintenance, repair, delivery) assigned to a
/// technician for a specific customer device.
///
/// A work order tracks:
/// - who created it (`createdByUserId`) vs. who executes it
///   (`assignedTechnicianId`)
/// - what device is being serviced (category / brand / model / serial)
/// - when it is scheduled (`scheduledDate` + optional
///   `scheduledTimeRange`)
/// - its current lifecycle position (`status`, `currentPauseReason`)
/// - creation / update / completion timestamps
///
/// Related items (notes, photos, GPS points, signatures, status
/// history, edit requests) live in their own entities that reference
/// this work order by `id`.
struct WorkOrder: Hashable, Sendable, Identifiable, Codable {
    let id: WorkOrderID
    var workOrderNumber: String

    var createdByUserId: UserID
    var assignedTechnicianId: UserID
    var customerId: CustomerID

    var workType: WorkType
    var deviceCategory: DeviceCategory
    var deviceBrand: String
    var deviceModel: String
    var serialNumber: String
    var issueDescription: String?

    var priority: WorkOrderPriority
    var scheduledDate: Date
    var scheduledTimeRange: ScheduledTimeRange?

    var status: WorkOrderStatus
    /// Populated only while `status == .paused`. Cleared on resume.
    var currentPauseReason: PauseReason?

    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: WorkOrderID,
        workOrderNumber: String,
        createdByUserId: UserID,
        assignedTechnicianId: UserID,
        customerId: CustomerID,
        workType: WorkType,
        deviceCategory: DeviceCategory,
        deviceBrand: String,
        deviceModel: String,
        serialNumber: String,
        issueDescription: String? = nil,
        priority: WorkOrderPriority,
        scheduledDate: Date,
        scheduledTimeRange: ScheduledTimeRange? = nil,
        status: WorkOrderStatus = .assigned,
        currentPauseReason: PauseReason? = nil,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.workOrderNumber = workOrderNumber
        self.createdByUserId = createdByUserId
        self.assignedTechnicianId = assignedTechnicianId
        self.customerId = customerId
        self.workType = workType
        self.deviceCategory = deviceCategory
        self.deviceBrand = deviceBrand
        self.deviceModel = deviceModel
        self.serialNumber = serialNumber
        self.issueDescription = issueDescription
        self.priority = priority
        self.scheduledDate = scheduledDate
        self.scheduledTimeRange = scheduledTimeRange
        self.status = status
        self.currentPauseReason = currentPauseReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

extension WorkOrder {
    /// A completed work order is locked from further normal-path
    /// mutations. Only an approved `EditRequest` may modify specific
    /// fields.
    var isLocked: Bool { status == .completed }
}
