import Foundation

/// Technician-side customer-satisfaction mutations triggered from field
/// workflows. The survey is first persisted locally and then represented by
/// an outbound queue row. Remote delivery is deliberately non-blocking: a
/// completed work order must remain completed when the device is offline or
/// a remote retry is needed. The SMS link is published only after a later
/// remote-id verification succeeds.
struct TechnicianCustomerSatisfactionService: Sendable {
    let createCustomerSatisfaction: CreateCustomerSatisfactionUseCase
    let syncOperationRepository: SyncOperationRepository
    let workOrderRepository: WorkOrderRepository
    let customerRepository: CustomerRepository
    let syncManager: (any SyncManaging)?
    let remoteCustomerSatisfactionRepository: (any CustomerSatisfactionRepository)?
    let networkReachability: (any NetworkReachabilityProviding)?

    init(
        createCustomerSatisfaction: CreateCustomerSatisfactionUseCase,
        syncOperationRepository: SyncOperationRepository,
        workOrderRepository: WorkOrderRepository,
        customerRepository: CustomerRepository,
        syncManager: (any SyncManaging)? = nil,
        remoteCustomerSatisfactionRepository: (any CustomerSatisfactionRepository)? = nil,
        networkReachability: (any NetworkReachabilityProviding)? = nil
    ) {
        self.createCustomerSatisfaction = createCustomerSatisfaction
        self.syncOperationRepository = syncOperationRepository
        self.workOrderRepository = workOrderRepository
        self.customerRepository = customerRepository
        self.syncManager = syncManager
        self.remoteCustomerSatisfactionRepository = remoteCustomerSatisfactionRepository
        self.networkReachability = networkReachability
    }

    func createOnWorkOrderCompletionWithSync(
        actor: User,
        orderId: WorkOrderID,
        at now: Date = Date(),
        dependsOnOperationId: SyncOperationID? = nil
    ) async throws -> CustomerSatisfaction? {
        guard let satisfaction = try await createCustomerSatisfaction.executeOnWorkOrderCompletion(
            actor: actor,
            orderId: orderId,
            at: now
        ) else {
            return nil
        }

        _ = try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .customerSatisfaction,
            entityId: satisfaction.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue,
            dependsOnOperationId: dependsOnOperationId
        )

        scheduleRemoteSyncAndSurveyDelivery(for: satisfaction, at: now)
        return satisfaction
    }

    /// The completion path has already durably saved its local data and queue
    /// row when this runs. A failed remote attempt remains retryable in that
    /// queue and is logged rather than being misreported as a failed work
    /// order completion.
    private func scheduleRemoteSyncAndSurveyDelivery(
        for satisfaction: CustomerSatisfaction,
        at now: Date
    ) {
        Task { [self] in
            do {
                try await syncAndSimulateSurveySMSIfRemote(for: satisfaction, at: now)
            } catch {
                AppLogger.sync.warning(
                    "Customer-satisfaction remote delivery deferred id=\(satisfaction.id.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    /// Offline completion intentionally stops after the local write + queue
    /// enqueue. Once remote sync succeeds, verify the exact document id
    /// before exposing the customer-facing link.
    private func syncAndSimulateSurveySMSIfRemote(
        for satisfaction: CustomerSatisfaction,
        at now: Date
    ) async throws {
        guard let syncManager,
              let remoteCustomerSatisfactionRepository,
              let networkReachability,
              await networkReachability.isReachable else {
            return
        }

        _ = try await syncManager.syncPending(now: now)
        let remote = try await remoteCustomerSatisfactionRepository.fetch(id: satisfaction.id)
        guard remote.id == satisfaction.id else {
            throw DomainError.invalidData(reason: "customerSatisfaction.remoteIdMismatch")
        }
        await simulateSurveySMS(for: satisfaction)
    }

    private func simulateSurveySMS(for satisfaction: CustomerSatisfaction) async {
        do {
            let order = try await workOrderRepository.fetch(id: satisfaction.workOrderId)
            let customer = try await customerRepository.fetch(id: satisfaction.customerId)
            CustomerSatisfactionSMSSimulator.simulateSend(
                customerName: customer.name,
                workOrderNumber: order.workOrderNumber,
                satisfactionId: satisfaction.id,
                recipientPhone: customer.phoneNumber?.rawValue
            )
        } catch {
            // SMS simulation must not affect completion.
        }
    }
}
