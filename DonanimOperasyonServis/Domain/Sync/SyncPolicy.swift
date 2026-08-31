import Foundation

/// Which `(entityType, operationType)` pairs may be enqueued.
///
/// This is **not** authorization (`RoleAccessPolicy` still decides
/// who may mutate). It answers "is this mutation a syncable remote
/// write at all?".
///
/// Completed work orders: a normal `workOrder` `update`/`delete`
/// while the order is `.completed` is **not** syncable. Field
/// changes go through the `editRequest` entity. Re-opening
/// completed via sync is a conflict (`CompletedWorkOrderSyncRule`),
/// never an automatic status write.
///
/// Exception: the technician/operator **completion transition**
/// itself must enqueue a `workOrder` `update` with status
/// `.completed` (`allowsCompletedWorkOrderUpdate: true`). Without
/// that write, remote never learns the order finished — and GPS
/// `.completed` create must stay ordered *before* that update.
enum SyncPolicy {

    static let allowedOperations: [SyncEntityType: Set<SyncOperationType>] = [
        .user:                     [.create, .update, .delete],
        .customer:                 [.create, .update, .delete],
        .workOrder:                [.create, .update, .delete],
        .workOrderNote:            [.create, .update, .delete],
        .workOrderStatusHistory:   [.create],
        .workOrderPhoto:           [.create, .update, .delete],
        .workOrderLocation:        [.create],
        .signature:                [.create, .update, .delete],
        .editRequest:              [.create, .update],
        .notification:             [.create, .update],
        .customerSatisfaction:     [.create, .update]
    ]

    static func canEnqueue(
        entityType: SyncEntityType,
        operationType: SyncOperationType,
        workOrderStatus: WorkOrderStatus? = nil,
        allowsCompletedWorkOrderUpdate: Bool = false
    ) -> Bool {
        guard allowedOperations[entityType]?.contains(operationType) == true else {
            return false
        }
        if entityType == .workOrder,
           operationType == .delete,
           workOrderStatus == .completed {
            return false
        }
        if entityType == .workOrder,
           operationType == .update,
           workOrderStatus == .completed,
           !allowsCompletedWorkOrderUpdate {
            return false
        }
        return true
    }

    /// Child records under a work order must enqueue with
    /// `payloadReference` = parent `WorkOrderID.rawValue` so the
    /// remote dispatcher can list them from the local SoT.
    static func requiresWorkOrderPayloadReference(_ entityType: SyncEntityType) -> Bool {
        switch entityType {
        case .workOrderNote,
             .workOrderPhoto,
             .workOrderLocation,
             .workOrderStatusHistory,
             .signature:
            return true
        case .user, .customer, .workOrder, .editRequest, .notification, .customerSatisfaction:
            return false
        }
    }
}
