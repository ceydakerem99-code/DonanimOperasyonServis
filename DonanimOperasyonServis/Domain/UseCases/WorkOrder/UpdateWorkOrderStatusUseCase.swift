import Foundation

/// Transitions a work order to a new status, subject to
/// `WorkOrderStateMachine` and `RoleAccessPolicy`. Also appends the
/// corresponding entry to the status-history audit trail.
///
/// This use case handles every transition *except* the final
/// `.inProgress → .completed` step; completion has to go through
/// `CompleteWorkOrderUseCase` so `CompletionRequirements` are
/// enforced. Attempting `.completed` here surfaces
/// `DomainError.invalidData` to make the mistake explicit.
struct UpdateWorkOrderStatusUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository
    let statusHistoryRepository: WorkOrderStatusHistoryRepository

    init(
        workOrderRepository: WorkOrderRepository,
        statusHistoryRepository: WorkOrderStatusHistoryRepository
    ) {
        self.workOrderRepository = workOrderRepository
        self.statusHistoryRepository = statusHistoryRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        newStatus: WorkOrderStatus,
        pauseReason: PauseReason? = nil,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        // Completion has its own use case with the requirements
        // check. Route callers there explicitly.
        guard newStatus != .completed else {
            throw DomainError.invalidData(reason: "workOrder.useCompleteWorkOrderUseCase")
        }

        var order = try await workOrderRepository.fetch(id: orderId)

        let action = Self.action(from: order.status, to: newStatus)

        // Role- and ownership-scoped authorization.
        guard RoleAccessPolicy.canAct(on: order, as: actor) else {
            throw order.isLocked
                ? DomainError.workOrderLocked(order.id)
                : DomainError.unauthorized(action: action)
        }
        guard RoleAccessPolicy.can(action, as: actor.role) else {
            throw DomainError.unauthorized(action: action)
        }

        // State-machine transition (throws on invalid).
        _ = try WorkOrderStateMachine.transition(from: order.status, to: newStatus)

        // Pause reason invariants.
        if newStatus == .paused {
            guard let reason = pauseReason else {
                throw DomainError.invalidData(reason: "workOrder.pauseReasonRequired")
            }
            order.currentPauseReason = reason
        } else {
            // Any transition away from paused clears the reason.
            order.currentPauseReason = nil
        }

        let previousStatus = order.status
        order.status = newStatus
        order.updatedAt = now

        try await workOrderRepository.save(order)

        let entry = WorkOrderStatusHistory(
            id: UUID().uuidString,
            workOrderId: order.id,
            fromStatus: previousStatus,
            toStatus: newStatus,
            pauseReason: order.currentPauseReason,
            actorUserId: actor.id,
            occurredAt: now
        )
        try await statusHistoryRepository.append(entry)

        return order
    }

    /// Maps a (from, to) status transition to the `DomainAction`
    /// that must be authorized for it. Only the transitions in
    /// `WorkOrderStateMachine.transitionTable` are meaningful; any
    /// other pair returns `.startServiceWork` as a safe default so
    /// authorization still fails deterministically before the state
    /// machine rejects the transition.
    static func action(from: WorkOrderStatus, to: WorkOrderStatus) -> DomainAction {
        switch (from, to) {
        case (.assigned, .accepted):     return .acceptWorkOrder
        case (.accepted, .enRoute):      return .startTravelToCustomer
        case (.enRoute, .arrived):       return .markArrivedAtCustomer
        case (.arrived, .inProgress):    return .startServiceWork
        case (.inProgress, .paused):     return .pauseServiceWork
        case (.paused, .inProgress):     return .resumeServiceWork
        case (.inProgress, .completed):  return .completeWorkOrder
        default:                         return .startServiceWork
        }
    }
}
