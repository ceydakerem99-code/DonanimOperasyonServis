import Foundation

/// Opens a pending `CustomerSatisfaction` survey for a completed work
/// order.
///
/// Rules:
/// - Only operators may create surveys manually (`RoleAccessPolicy`).
/// - The target work order must be completed (locked).
/// - `workOrderId`, `customerId`, and the assigned technician are
///   taken from the work order; the survey entity does not duplicate
///   `technicianId`.
/// - At most one `.pending` survey may exist per work order for the
///   operator path.
/// - Work-order completion auto-create skips when any survey already
///   exists for the order.
struct CreateCustomerSatisfactionUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository
    let customerSatisfactionRepository: CustomerSatisfactionRepository

    init(
        workOrderRepository: WorkOrderRepository,
        customerSatisfactionRepository: CustomerSatisfactionRepository
    ) {
        self.workOrderRepository = workOrderRepository
        self.customerSatisfactionRepository = customerSatisfactionRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        satisfactionId: CustomerSatisfactionID,
        at now: Date = Date()
    ) async throws -> CustomerSatisfaction {
        guard RoleAccessPolicy.can(.createCustomerSatisfaction, as: actor.role) else {
            throw DomainError.unauthorized(action: .createCustomerSatisfaction)
        }

        let order = try await workOrderRepository.fetch(id: orderId)
        guard RoleAccessPolicy.canCreateCustomerSatisfaction(on: order, as: actor) else {
            if !order.isLocked {
                throw DomainError.invalidCustomerSatisfaction(reason: .workOrderNotCompleted)
            }
            throw DomainError.unauthorized(action: .createCustomerSatisfaction)
        }

        let existing = try await customerSatisfactionRepository.list(for: order.id)
        if existing.contains(where: { $0.status == .pending }) {
            throw DomainError.invalidCustomerSatisfaction(reason: .pendingAlreadyExists)
        }

        return try await savePending(for: order, satisfactionId: satisfactionId, at: now)
    }

    /// Creates a pending survey after a work order is successfully
    /// completed by its assigned technician.
    ///
    /// Returns `nil` when a survey already exists for the work order
    /// (idempotent). Throws only when the order is not completed.
    @discardableResult
    func executeOnWorkOrderCompletion(
        actor: User,
        orderId: WorkOrderID,
        satisfactionId: CustomerSatisfactionID = CustomerSatisfactionID(UUID().uuidString),
        at now: Date = Date()
    ) async throws -> CustomerSatisfaction? {
        let order = try await workOrderRepository.fetch(id: orderId)
        guard order.isLocked else {
            throw DomainError.invalidCustomerSatisfaction(reason: .workOrderNotCompleted)
        }
        guard order.assignedTechnicianId == actor.id else {
            throw DomainError.unauthorized(action: .completeWorkOrder)
        }

        let existing = try await customerSatisfactionRepository.list(for: order.id)
        guard existing.isEmpty else {
            return nil
        }

        return try await savePending(for: order, satisfactionId: satisfactionId, at: now)
    }

    private func savePending(
        for order: WorkOrder,
        satisfactionId: CustomerSatisfactionID,
        at now: Date
    ) async throws -> CustomerSatisfaction {
        _ = order.assignedTechnicianId

        let satisfaction = CustomerSatisfaction(
            id: satisfactionId,
            workOrderId: order.id,
            customerId: order.customerId,
            status: .pending,
            rating: nil,
            comment: nil,
            createdAt: now,
            updatedAt: now,
            submittedAt: nil
        )
        try await customerSatisfactionRepository.save(satisfaction)
        return satisfaction
    }
}
