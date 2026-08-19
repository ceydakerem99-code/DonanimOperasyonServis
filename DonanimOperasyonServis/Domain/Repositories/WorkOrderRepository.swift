import Foundation

/// Filter parameters accepted by `WorkOrderRepository.list(_:)`.
/// Every field is optional so callers can compose the exact query
/// they need without a proliferation of methods.
struct WorkOrderFilter: Hashable, Sendable {
    var status: WorkOrderStatus?
    var priority: WorkOrderPriority?
    var workType: WorkType?
    var assignedTechnicianId: UserID?
    var createdByUserId: UserID?
    var customerId: CustomerID?
    /// Inclusive scheduled-date window. Both endpoints optional.
    var scheduledFrom: Date?
    var scheduledTo: Date?

    init(
        status: WorkOrderStatus? = nil,
        priority: WorkOrderPriority? = nil,
        workType: WorkType? = nil,
        assignedTechnicianId: UserID? = nil,
        createdByUserId: UserID? = nil,
        customerId: CustomerID? = nil,
        scheduledFrom: Date? = nil,
        scheduledTo: Date? = nil
    ) {
        self.status = status
        self.priority = priority
        self.workType = workType
        self.assignedTechnicianId = assignedTechnicianId
        self.createdByUserId = createdByUserId
        self.customerId = customerId
        self.scheduledFrom = scheduledFrom
        self.scheduledTo = scheduledTo
    }

    static let all = WorkOrderFilter()
}

/// Persistence surface for `WorkOrder` records. Related items
/// (notes, photos, GPS points, signatures, status history, edit
/// requests) are handled by their own repository protocols so
/// implementations can pick the most natural storage model
/// (embedded arrays, subcollections, etc.).
protocol WorkOrderRepository: Sendable {
    func fetch(id: WorkOrderID) async throws -> WorkOrder
    func list(filter: WorkOrderFilter) async throws -> [WorkOrder]
    func save(_ workOrder: WorkOrder) async throws
    func delete(id: WorkOrderID) async throws
}
