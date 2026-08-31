import Foundation

/// Sync-enqueue helpers for admin mutations.
enum AdminSyncEnqueue {

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
        now: Date,
        actorUserId: String
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
            localVersion: version,
            actorUserId: actorUserId
        )
        _ = try await queue.enqueue(operation)
    }

    static func enqueueUpdate(
        entityType: SyncEntityType,
        entityId: String,
        queue: SyncOperationRepository,
        now: Date,
        actorUserId: String
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
            actorUserId: actorUserId
        )
        _ = try await queue.enqueue(operation)
    }

    static func enqueueDelete(
        entityType: SyncEntityType,
        entityId: String,
        queue: SyncOperationRepository,
        now: Date,
        actorUserId: String
    ) async throws {
        let version = try await nextLocalVersion(
            entityType: entityType,
            entityId: entityId,
            queue: queue
        )
        let operation = try SyncOperation.pending(
            entityType: entityType,
            entityId: entityId,
            operationType: .delete,
            createdAt: now,
            localVersion: version,
            actorUserId: actorUserId
        )
        _ = try await queue.enqueue(operation)
    }
}
