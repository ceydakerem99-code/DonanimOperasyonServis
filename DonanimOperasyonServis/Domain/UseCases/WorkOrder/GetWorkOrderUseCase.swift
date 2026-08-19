import Foundation

/// Fetches a single work order by ID and enforces role-appropriate
/// visibility.
///
/// Rules mirror `GetWorkOrdersUseCase`:
/// - Operator may fetch any work order.
/// - Technician may fetch only work orders assigned to them.
/// - Admin does not access the operational surface; use the
///   reporting use cases instead.
struct GetWorkOrderUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository

    init(workOrderRepository: WorkOrderRepository) {
        self.workOrderRepository = workOrderRepository
    }

    func execute(actor: User, id: WorkOrderID) async throws -> WorkOrder {
        let order = try await workOrderRepository.fetch(id: id)

        switch actor.role {
        case .operator:
            guard RoleAccessPolicy.can(.viewAllWorkOrders, as: actor.role) else {
                throw DomainError.unauthorized(action: .viewAllWorkOrders)
            }
            return order

        case .technician:
            guard RoleAccessPolicy.can(.viewOwnAssignedWorkOrders, as: actor.role),
                  order.assignedTechnicianId == actor.id
            else {
                throw DomainError.unauthorized(action: .viewOwnAssignedWorkOrders)
            }
            return order

        case .admin:
            throw DomainError.unauthorized(action: .viewAllWorkOrders)
        }
    }
}
