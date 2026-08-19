import Foundation

/// (Re)assigns a work order to a technician. Only operators may
/// perform this action, and completed work orders cannot be
/// reassigned (they are locked).
struct AssignWorkOrderUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository

    init(workOrderRepository: WorkOrderRepository) {
        self.workOrderRepository = workOrderRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        newTechnicianId: UserID,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        guard RoleAccessPolicy.can(.assignWorkOrder, as: actor.role) else {
            throw DomainError.unauthorized(action: .assignWorkOrder)
        }

        var order = try await workOrderRepository.fetch(id: orderId)
        if order.isLocked {
            throw DomainError.workOrderLocked(order.id)
        }

        order.assignedTechnicianId = newTechnicianId
        order.updatedAt = now
        try await workOrderRepository.save(order)
        return order
    }
}
