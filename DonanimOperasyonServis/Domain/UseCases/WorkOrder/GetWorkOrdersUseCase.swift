import Foundation

/// Lists work orders visible to the calling user, applying the
/// role-appropriate scope automatically.
///
/// Rules:
/// - **Operator** sees everything the caller-provided `filter`
///   yields (`viewAllWorkOrders`).
/// - **Technician** is silently scoped to their own assignments; any
///   `filter.assignedTechnicianId` the caller supplied is
///   overwritten with the technician's own ID to prevent leaking
///   other technicians' work.
/// - **Admin** does not have access to the operational work-orders
///   list in v1 — admin's read-only visibility is expressed through
///   the reporting surface (`viewSystemReports`), which is a
///   separate use case added in a later phase.
struct GetWorkOrdersUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository

    init(workOrderRepository: WorkOrderRepository) {
        self.workOrderRepository = workOrderRepository
    }

    func execute(
        actor: User,
        filter: WorkOrderFilter = .all
    ) async throws -> [WorkOrder] {
        switch actor.role {
        case .operator:
            guard RoleAccessPolicy.can(.viewAllWorkOrders, as: actor.role) else {
                throw DomainError.unauthorized(action: .viewAllWorkOrders)
            }
            return try await workOrderRepository.list(filter: filter)

        case .technician:
            guard RoleAccessPolicy.can(.viewOwnAssignedWorkOrders, as: actor.role) else {
                throw DomainError.unauthorized(action: .viewOwnAssignedWorkOrders)
            }
            var scoped = filter
            scoped.assignedTechnicianId = actor.id
            return try await workOrderRepository.list(filter: scoped)

        case .admin:
            throw DomainError.unauthorized(action: .viewAllWorkOrders)
        }
    }
}
