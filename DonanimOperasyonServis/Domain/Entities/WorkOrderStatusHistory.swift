import Foundation

/// Immutable audit record of a single status transition on a work
/// order. One entry is appended every time
/// `UpdateWorkOrderStatusUseCase` (or `CompleteWorkOrderUseCase`)
/// successfully mutates a work order's status.
///
/// `fromStatus` is `nil` for the initial `.assigned` row created at
/// work-order creation time. `pauseReason` is populated only when
/// `toStatus == .paused`.
struct WorkOrderStatusHistory: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let workOrderId: WorkOrderID
    let fromStatus: WorkOrderStatus?
    let toStatus: WorkOrderStatus
    let pauseReason: PauseReason?
    let actorUserId: UserID
    let occurredAt: Date

    init(
        id: String,
        workOrderId: WorkOrderID,
        fromStatus: WorkOrderStatus?,
        toStatus: WorkOrderStatus,
        pauseReason: PauseReason? = nil,
        actorUserId: UserID,
        occurredAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.pauseReason = pauseReason
        self.actorUserId = actorUserId
        self.occurredAt = occurredAt
    }
}
