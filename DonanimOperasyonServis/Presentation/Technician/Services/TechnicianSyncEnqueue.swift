import Foundation

/// Shared sync-enqueue helpers for technician field operations.
enum TechnicianSyncEnqueue {

    static func nextLocalVersion(
        entityType: SyncEntityType,
        entityId: String,
        queue: SyncOperationRepository
    ) async throws -> Int {
        let existing = try await queue.list(entityType: entityType, entityId: entityId)
        return (existing.map(\.localVersion).max() ?? 0) + 1
    }

    static func enqueueCreate(
        entityType: SyncEntityType,
        entityId: String,
        queue: SyncOperationRepository,
        now: Date
    ) async throws {
        let version = try await nextLocalVersion(
            entityType: entityType,
            entityId: entityId,
            queue: queue
        )
        let operation = try SyncOperation.pending(
            entityType: entityType,
            entityId: entityId,
            operationType: .create,
            createdAt: now,
            localVersion: version
        )
        _ = try await queue.enqueue(operation)
    }

    static func enqueueUpdate(
        entityType: SyncEntityType,
        entityId: String,
        queue: SyncOperationRepository,
        now: Date,
        workOrderStatus: WorkOrderStatus? = nil
    ) async throws {
        let version = try await nextLocalVersion(
            entityType: entityType,
            entityId: entityId,
            queue: queue
        )
        let operation = try SyncOperation.pending(
            entityType: entityType,
            entityId: entityId,
            operationType: .update,
            createdAt: now,
            localVersion: version,
            workOrderStatus: workOrderStatus
        )
        _ = try await queue.enqueue(operation)
    }
}
