import Foundation

/// Admin work-order mutations with offline-first sync enqueue.
struct AdminWorkOrderService: Sendable {
    let deleteWorkOrder: DeleteWorkOrderUseCase
    let workOrderRepository: WorkOrderRepository
    let syncOperationRepository: SyncOperationRepository

    func deleteWithSync(
        actor: User,
        orderId: WorkOrderID,
        at now: Date = Date()
    ) async throws {
        let order = try await workOrderRepository.fetch(id: orderId)
        let statusBeforeDelete = order.status

        try await deleteWorkOrder.execute(actor: actor, orderId: orderId, at: now)

        guard SyncPolicy.canEnqueue(
            entityType: .workOrder,
            operationType: .delete,
            workOrderStatus: statusBeforeDelete
        ) else {
            return
        }

        try await AdminSyncEnqueue.enqueueDelete(
            entityType: .workOrder,
            entityId: orderId.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
    }
}
