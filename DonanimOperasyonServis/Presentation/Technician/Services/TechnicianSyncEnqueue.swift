import Foundation

/// Shared sync-enqueue helpers for technician field operations.
///
/// Work-order children must pass `payloadReference` = parent
/// work-order id (`SyncPolicy.requiresWorkOrderPayloadReference`).
enum TechnicianSyncEnqueue {

    static func nextLocalVersion(
        entityType: SyncEntityType,
        entityId: String,
        queue: SyncOperationRepository
    ) async throws -> Int {
        let existing = try await queue.list(entityType: entityType, entityId: entityId)
        return (existing.map(\.localVersion).max() ?? 0) + 1
    }

    @discardableResult
    static func enqueueCreate(
        entityType: SyncEntityType,
        entityId: String,
        queue: SyncOperationRepository,
        now: Date,
        actorUserId: String,
        payloadReference: String? = nil,
        dependsOnOperationId: SyncOperationID? = nil
    ) async throws -> SyncOperation {
        let version = try await nextLocalVersion(
            entityType: entityType,
            entityId: entityId,
            queue: queue
        )
        let operation = try SyncOperation.pending(
            entityType: entityType,
            entityId: entityId,
            operationType: .create,
            payloadReference: payloadReference,
            createdAt: now,
            localVersion: version,
            dependsOnOperationId: dependsOnOperationId,
            actorUserId: actorUserId
        )
        _ = try await queue.enqueue(operation)
        return operation
    }

    @discardableResult
    static func enqueueUpdate(
        entityType: SyncEntityType,
        entityId: String,
        queue: SyncOperationRepository,
        now: Date,
        actorUserId: String,
        workOrderStatus: WorkOrderStatus? = nil,
        payloadReference: String? = nil,
        dependsOnOperationId: SyncOperationID? = nil,
        allowsCompletedWorkOrderUpdate: Bool = false
    ) async throws -> SyncOperation {
        let version = try await nextLocalVersion(
            entityType: entityType,
            entityId: entityId,
            queue: queue
        )
        let operation = try SyncOperation.pending(
            entityType: entityType,
            entityId: entityId,
            operationType: .update,
            payloadReference: payloadReference,
            createdAt: now,
            localVersion: version,
            workOrderStatus: workOrderStatus,
            dependsOnOperationId: dependsOnOperationId,
            allowsCompletedWorkOrderUpdate: allowsCompletedWorkOrderUpdate,
            actorUserId: actorUserId
        )
        _ = try await queue.enqueue(operation)
        return operation
    }
}
