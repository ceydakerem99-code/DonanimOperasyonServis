import Foundation

/// Fetches a single work order for admin reporting surfaces.
struct GetSystemWorkOrderUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository

    init(workOrderRepository: WorkOrderRepository) {
        self.workOrderRepository = workOrderRepository
    }

    func execute(actor: User, id: WorkOrderID) async throws -> WorkOrder {
        guard RoleAccessPolicy.can(.viewSystemReports, as: actor.role) else {
            throw DomainError.unauthorized(action: .viewSystemReports)
        }
        return try await workOrderRepository.fetch(id: id)
    }
}
