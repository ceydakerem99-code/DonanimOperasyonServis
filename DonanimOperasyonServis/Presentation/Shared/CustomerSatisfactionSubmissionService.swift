import Foundation

/// Customer-facing satisfaction submission (web form / SMS link).
///
/// Deliberately separate from `OperatorCustomerSatisfactionService`: the
/// respondent has no authenticated `User` actor. Survey access must be
/// gated at the presentation boundary (token / link), not via
/// `RoleAccessPolicy`.
struct CustomerSatisfactionSubmissionService: Sendable {
    let submitCustomerSatisfaction: SubmitCustomerSatisfactionUseCase
    let workOrderRepository: WorkOrderRepository
    let syncOperationRepository: SyncOperationRepository

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
        try await TechnicianSyncEnqueue.enqueueUpdate(
            entityType: .customerSatisfaction,
            entityId: satisfaction.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: order.createdByUserId.rawValue
        )
        return satisfaction
    }
}

extension DIContainer {
    func makeCustomerSatisfactionSubmissionService() -> CustomerSatisfactionSubmissionService {
        CustomerSatisfactionSubmissionService(
            submitCustomerSatisfaction: SubmitCustomerSatisfactionUseCase(
                customerSatisfactionRepository: customerSatisfactionRepository
            ),
            workOrderRepository: workOrderRepository,
            syncOperationRepository: syncOperationRepository
        )
    }
}
