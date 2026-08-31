import Foundation

/// Operator customer-satisfaction mutations with offline-first sync enqueue.
struct OperatorCustomerSatisfactionService: Sendable {
    let createCustomerSatisfaction: CreateCustomerSatisfactionUseCase
    let submitCustomerSatisfaction: SubmitCustomerSatisfactionUseCase
    let workOrderRepository: WorkOrderRepository
    let syncOperationRepository: SyncOperationRepository

    @discardableResult
    func createWithSync(
        actor: User,
        orderId: WorkOrderID,
        satisfactionId: CustomerSatisfactionID = CustomerSatisfactionID(UUID().uuidString),
        at now: Date = Date()
    ) async throws -> CustomerSatisfaction {
        let satisfaction = try await createCustomerSatisfaction.execute(
            actor: actor,
            orderId: orderId,
            satisfactionId: satisfactionId,
            at: now
        )
        try await AdminSyncEnqueue.enqueueCreate(
            entityType: .customerSatisfaction,
            entityId: satisfaction.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
        return satisfaction
    }

    @discardableResult
    func submitWithSync(
        satisfactionId: CustomerSatisfactionID,
        rating: CustomerSatisfactionRating,
        comment: String? = nil,
        at now: Date = Date()
    ) async throws -> CustomerSatisfaction {
        let satisfaction = try await submitCustomerSatisfaction.execute(
            satisfactionId: satisfactionId,
            rating: rating,
            comment: comment,
            at: now
        )
        let order = try await workOrderRepository.fetch(id: satisfaction.workOrderId)
        try await AdminSyncEnqueue.enqueueUpdate(
            entityType: .customerSatisfaction,
            entityId: satisfaction.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: order.createdByUserId.rawValue
        )
        return satisfaction
    }
}
