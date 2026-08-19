import Foundation

/// Application-layer coordinator for operator work-order writes.
/// Persists locally via domain use cases, then enqueues sync
/// operations through the existing queue — no new SyncManager.
struct OperatorWorkOrderService: Sendable {
    let createWorkOrder: CreateWorkOrderUseCase
    let statusHistoryRepository: WorkOrderStatusHistoryRepository
    let syncOperationRepository: SyncOperationRepository

    init(
        createWorkOrder: CreateWorkOrderUseCase,
        statusHistoryRepository: WorkOrderStatusHistoryRepository,
        syncOperationRepository: SyncOperationRepository
    ) {
        self.createWorkOrder = createWorkOrder
        self.statusHistoryRepository = statusHistoryRepository
        self.syncOperationRepository = syncOperationRepository
    }

    @discardableResult
    func createWithSync(
        actor: User,
        request: NewWorkOrderRequest,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        let order = try await createWorkOrder.execute(actor: actor, request: request, at: now)

        let workOrderOperation = try SyncOperation.pending(
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1
        )
        _ = try await syncOperationRepository.enqueue(workOrderOperation)

        let history = try await statusHistoryRepository.list(for: order.id)
        if let initial = history.first {
            let historyOperation = try SyncOperation.pending(
                entityType: .workOrderStatusHistory,
                entityId: initial.id,
                operationType: .create,
                createdAt: now,
                localVersion: 1
            )
            _ = try await syncOperationRepository.enqueue(historyOperation)
        }

        return order
    }
}
