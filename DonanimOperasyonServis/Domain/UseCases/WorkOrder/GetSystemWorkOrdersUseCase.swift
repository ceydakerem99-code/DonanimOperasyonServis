import Foundation

/// Read-only work-order listing for admin reporting surfaces.
struct GetSystemWorkOrdersUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository

    init(workOrderRepository: WorkOrderRepository) {
        self.workOrderRepository = workOrderRepository
    }

    func execute(actor: User, filter: WorkOrderFilter = .all) async throws -> [WorkOrder] {
        guard RoleAccessPolicy.can(.viewSystemReports, as: actor.role) else {
            throw DomainError.unauthorized(action: .viewSystemReports)
        }
        return try await workOrderRepository.list(filter: filter)
    }
}
