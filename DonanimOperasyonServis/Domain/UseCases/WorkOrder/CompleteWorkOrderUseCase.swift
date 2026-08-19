import Foundation

/// Completes a work order. This is the single canonical path for the
/// `inProgress → completed` transition and is the only place where
/// `CompletionRequirements` is enforced.
///
/// On success:
/// - the work order is transitioned to `.completed`
/// - `completedAt` and `updatedAt` are stamped with `now`
/// - `currentPauseReason` is cleared (defensive; should be `nil`
///   already if the source status was `.inProgress`)
/// - a `WorkOrderStatusHistory` entry is appended
///
/// On failure the work order is not mutated and no history entry
/// is written.
struct CompleteWorkOrderUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository
    let statusHistoryRepository: WorkOrderStatusHistoryRepository
    let noteRepository: WorkOrderNoteRepository
    let photoRepository: WorkOrderPhotoRepository
    let locationRepository: WorkOrderLocationRepository
    let signatureRepository: SignatureRepository

    init(
        workOrderRepository: WorkOrderRepository,
        statusHistoryRepository: WorkOrderStatusHistoryRepository,
        noteRepository: WorkOrderNoteRepository,
        photoRepository: WorkOrderPhotoRepository,
        locationRepository: WorkOrderLocationRepository,
        signatureRepository: SignatureRepository
    ) {
        self.workOrderRepository = workOrderRepository
        self.statusHistoryRepository = statusHistoryRepository
        self.noteRepository = noteRepository
        self.photoRepository = photoRepository
        self.locationRepository = locationRepository
        self.signatureRepository = signatureRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        guard RoleAccessPolicy.can(.completeWorkOrder, as: actor.role) else {
            throw DomainError.unauthorized(action: .completeWorkOrder)
        }

        var order = try await workOrderRepository.fetch(id: orderId)
        guard RoleAccessPolicy.canAct(on: order, as: actor) else {
            throw order.isLocked
                ? DomainError.workOrderLocked(order.id)
                : DomainError.unauthorized(action: .completeWorkOrder)
        }

        // Validate the state-machine transition up front so we
        // don't waste repository calls on an already-invalid state.
        _ = try WorkOrderStateMachine.transition(from: order.status, to: .completed)

        // Gather every piece of evidence the checklist inspects.
        // Snapshot the ID up front so each concurrent async-let
        // sends a Sendable primitive rather than closing over the
        // mutable `order` var (which would trip Swift 6's strict
        // concurrency check).
        let scopedOrderId = order.id
        async let notes      = noteRepository.list(for: scopedOrderId)
        async let photos     = photoRepository.list(for: scopedOrderId)
        async let locations  = locationRepository.list(for: scopedOrderId)
        async let signatures = signatureRepository.list(for: scopedOrderId)

        let context = CompletionContext(
            workType: order.workType,
            notes: try await notes,
            photos: try await photos,
            locations: try await locations,
            signatures: try await signatures
        )

        switch CompletionRequirements.check(context) {
        case .success:
            break
        case .failure(let missing):
            throw DomainError.incompleteWorkOrder(missing.items)
        }

        let previousStatus = order.status
        order.status = .completed
        order.completedAt = now
        order.updatedAt = now
        order.currentPauseReason = nil

        try await workOrderRepository.save(order)

        let entry = WorkOrderStatusHistory(
            id: UUID().uuidString,
            workOrderId: order.id,
            fromStatus: previousStatus,
            toStatus: .completed,
            pauseReason: nil,
            actorUserId: actor.id,
            occurredAt: now
        )
        try await statusHistoryRepository.append(entry)

        return order
    }
}
