import Foundation

/// Application-layer coordinator for operator work-order writes.
/// Persists locally via domain use cases, then enqueues sync
/// operations through the existing queue — no new SyncManager.
/// FAZ 3B also submits workOrder create to the WebSocket gateway (ACK required
/// when connected). SyncQueue enqueue is unchanged.
struct OperatorWorkOrderService: Sendable {
    let createWorkOrder: CreateWorkOrderUseCase
    let assignWorkOrder: AssignWorkOrderUseCase
    let updateWorkOrderPlanning: UpdateWorkOrderPlanningUseCase
    let statusHistoryRepository: WorkOrderStatusHistoryRepository
    let syncOperationRepository: SyncOperationRepository
    let notificationRepository: NotificationRepository
    let realtimeWorkOrderCreate: (any RealtimeWorkOrderCreateSubmitting)?
    let syncLifecycle: (any SyncLifecycleCoordinating)?

    init(
        createWorkOrder: CreateWorkOrderUseCase,
        assignWorkOrder: AssignWorkOrderUseCase,
        updateWorkOrderPlanning: UpdateWorkOrderPlanningUseCase,
        statusHistoryRepository: WorkOrderStatusHistoryRepository,
        syncOperationRepository: SyncOperationRepository,
        notificationRepository: NotificationRepository,
        realtimeWorkOrderCreate: (any RealtimeWorkOrderCreateSubmitting)? = nil,
        syncLifecycle: (any SyncLifecycleCoordinating)? = nil
    ) {
        self.createWorkOrder = createWorkOrder
        self.assignWorkOrder = assignWorkOrder
        self.updateWorkOrderPlanning = updateWorkOrderPlanning
        self.statusHistoryRepository = statusHistoryRepository
        self.syncOperationRepository = syncOperationRepository
        self.notificationRepository = notificationRepository
        self.realtimeWorkOrderCreate = realtimeWorkOrderCreate
        self.syncLifecycle = syncLifecycle
    }

    @discardableResult
    func createWithSync(
        actor: User,
        request: NewWorkOrderRequest,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        let order = try await createWorkOrder.execute(actor: actor, request: request, at: now)

        let workOrderOperation = try SyncOperation.pending(
            entityType: .workOrder,
            entityId: order.id.rawValue,
            operationType: .create,
            createdAt: now,
            localVersion: 1,
            actorUserId: actor.id.rawValue
        )
        _ = try await syncOperationRepository.enqueue(workOrderOperation)

        if let realtimeWorkOrderCreate {
            _ = await realtimeWorkOrderCreate.submitWorkOrderCreate(
                order,
                actorUserId: actor.id.rawValue
            )
        }

        let history = try await statusHistoryRepository.list(for: order.id)
        if let initial = history.first {
            try await TechnicianSyncEnqueue.enqueueCreate(
                entityType: .workOrderStatusHistory,
                entityId: initial.id,
                queue: syncOperationRepository,
                now: now,
                actorUserId: actor.id.rawValue,
                payloadReference: order.id.rawValue
            )
        }

        try await createAssignmentNotification(
            for: order,
            technicianId: order.assignedTechnicianId,
            actorName: actor.fullName,
            actorUserId: actor.id,
            at: now,
            dependsOnOperationId: workOrderOperation.id
        )
        await requestSyncDrainIfNeeded()
        return order
    }

    /// Reassigns the technician via domain rules, then enqueues a work-order update.
    @discardableResult
    func assignWithSync(
        actor: User,
        orderId: WorkOrderID,
        newTechnicianId: UserID,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        let order = try await assignWorkOrder.execute(
            actor: actor,
            orderId: orderId,
            newTechnicianId: newTechnicianId,
            at: now
        )
        let workOrderOperation = try await TechnicianSyncEnqueue.enqueueUpdate(
            entityType: .workOrder,
            entityId: order.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue,
            workOrderStatus: order.status
        )
        try await createAssignmentNotification(
            for: order,
            technicianId: order.assignedTechnicianId,
            actorName: actor.fullName,
            actorUserId: actor.id,
            at: now,
            dependsOnOperationId: workOrderOperation.id
        )
        await requestSyncDrainIfNeeded()
        return order
    }

    @discardableResult
    func updatePlanningWithSync(
        actor: User,
        orderId: WorkOrderID,
        update: WorkOrderPlanningUpdate,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        let order = try await updateWorkOrderPlanning.execute(
            actor: actor,
            orderId: orderId,
            update: update,
            at: now
        )
        try await TechnicianSyncEnqueue.enqueueUpdate(
            entityType: .workOrder,
            entityId: order.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue,
            workOrderStatus: order.status
        )
        return order
    }

    private func createAssignmentNotification(
        for order: WorkOrder,
        technicianId: UserID,
        actorName: String,
        actorUserId: UserID,
        at now: Date,
        dependsOnOperationId: SyncOperationID? = nil
    ) async throws {
        let notification = AppNotification(
            id: NotificationID(UUID().uuidString),
            recipientUserId: technicianId,
            type: .workOrderAssigned,
            title: "Yeni İş Emri Atandı",
            body: "\(order.workOrderNumber) · \(order.workType.displayName) · \(actorName) tarafından atandı.",
            relatedWorkOrderId: order.id,
            createdAt: now
        )
        try await notificationRepository.save(notification)
        try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .notification,
            entityId: notification.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actorUserId.rawValue,
            payloadReference: technicianId.rawValue,
            dependsOnOperationId: dependsOnOperationId
        )
    }

    private func requestSyncDrainIfNeeded() async {
        await syncLifecycle?.handleNetworkBecameReachable()
    }
}
