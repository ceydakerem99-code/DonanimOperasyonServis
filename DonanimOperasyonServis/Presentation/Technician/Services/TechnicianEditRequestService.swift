import Foundation

/// Technician edit-request mutations with offline-first sync enqueue.
struct TechnicianEditRequestService: Sendable {
    let createEditRequest: CreateEditRequestUseCase
    let workOrderRepository: WorkOrderRepository
    let notificationRepository: NotificationRepository
    let syncOperationRepository: SyncOperationRepository

    @discardableResult
    func createWithSync(
        actor: User,
        orderId: WorkOrderID,
        field: EditableWorkOrderField,
        currentValue: String,
        requestedValue: String,
        reason: String,
        requestId: EditRequestID = EditRequestID(UUID().uuidString),
        at now: Date = Date()
    ) async throws -> EditRequest {
        let request = try await createEditRequest.execute(
            actor: actor,
            orderId: orderId,
            requestId: requestId,
            field: field,
            currentValue: currentValue,
            requestedValue: requestedValue,
            reason: reason,
            at: now
        )
        let editRequestOperation = try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .editRequest,
            entityId: request.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
        try await createEditRequestNotification(
            request: request,
            orderId: orderId,
            field: field,
            actor: actor,
            at: now,
            dependsOnOperationId: editRequestOperation.id
        )
        return request
    }

    private func createEditRequestNotification(
        request: EditRequest,
        orderId: WorkOrderID,
        field: EditableWorkOrderField,
        actor: User,
        at now: Date,
        dependsOnOperationId: SyncOperationID
    ) async throws {
        let order = try await workOrderRepository.fetch(id: orderId)
        let operatorId = order.createdByUserId
        guard operatorId != actor.id else { return }

        let notification = AppNotification(
            id: NotificationID(UUID().uuidString),
            recipientUserId: operatorId,
            type: .editRequestCreated,
            title: "Yeni Düzenleme Talebi",
            body: "\(order.workOrderNumber) · \(field.displayName) alanı için düzenleme talebi.",
            relatedWorkOrderId: order.id,
            relatedEditRequestId: request.id,
            createdAt: now
        )
        try await notificationRepository.save(notification)
        try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .notification,
            entityId: notification.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue,
            payloadReference: operatorId.rawValue,
            dependsOnOperationId: dependsOnOperationId
        )
    }
}
