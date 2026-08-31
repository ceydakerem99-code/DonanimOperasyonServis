import Foundation

struct WorkOrderPlanningUpdate: Equatable, Sendable {
    var priority: WorkOrderPriority?
    var scheduledDate: Date?
    var scheduledTimeRange: ScheduledTimeRange?

    var hasChanges: Bool {
        priority != nil || scheduledDate != nil || scheduledTimeRange != nil
    }
}

/// Updates planning fields on non-terminal work orders (priority / schedule).
struct UpdateWorkOrderPlanningUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository

    init(workOrderRepository: WorkOrderRepository) {
        self.workOrderRepository = workOrderRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        update: WorkOrderPlanningUpdate,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        guard RoleAccessPolicy.can(.assignWorkOrder, as: actor.role) else {
            throw DomainError.unauthorized(action: .assignWorkOrder)
        }
        guard update.hasChanges else {
            throw DomainError.invalidData(reason: "workOrder.planningUpdateEmpty")
        }

        var order = try await workOrderRepository.fetch(id: orderId)
        if order.isLocked {
            throw DomainError.workOrderLocked(order.id)
        }
        guard WorkOrderBulkMutationPolicy.supportsBulkPlanningMutation(order) else {
            throw DomainError.invalidData(reason: "workOrder.bulkMutationNotAllowed")
        }

        if let priority = update.priority {
            order.priority = priority
        }
        if let scheduledDate = update.scheduledDate {
            order.scheduledDate = scheduledDate
        }
        if let scheduledTimeRange = update.scheduledTimeRange {
            order.scheduledTimeRange = scheduledTimeRange
        }

        order.updatedAt = now
        try await workOrderRepository.save(order)
        return order
    }
}
