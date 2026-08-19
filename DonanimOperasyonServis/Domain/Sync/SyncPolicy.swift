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
        .notification:             [.create, .update]
    ]

    static func canEnqueue(
        entityType: SyncEntityType,
        operationType: SyncOperationType,
        workOrderStatus: WorkOrderStatus? = nil
    ) -> Bool {
        guard allowedOperations[entityType]?.contains(operationType) == true else {
            return false
        }
        if entityType == .workOrder,
           operationType == .update || operationType == .delete,
           workOrderStatus == .completed {
            return false
        }
        return true
    }
}
