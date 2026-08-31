import Foundation

/// Deletes a work order from local storage. Admin-only.
///
/// Completed orders cannot be deleted — remote sync rejects
/// `workOrder` delete while `.completed` (`SyncPolicy`).
struct DeleteWorkOrderUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository

    init(workOrderRepository: WorkOrderRepository) {
        self.workOrderRepository = workOrderRepository
    }

    func execute(
        actor: User,
        orderId: WorkOrderID,
        at now: Date = Date()
    ) async throws {
        guard RoleAccessPolicy.can(.deleteWorkOrder, as: actor.role) else {
            throw DomainError.unauthorized(action: .deleteWorkOrder)
        }

        let order = try await workOrderRepository.fetch(id: orderId)
        if order.status == .completed {
            throw DomainError.workOrderLocked(order.id)
        }

        _ = now
        try await workOrderRepository.delete(id: orderId)
    }
}
