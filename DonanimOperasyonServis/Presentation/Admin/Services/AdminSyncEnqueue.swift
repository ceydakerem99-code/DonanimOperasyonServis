import Foundation

/// Sync-enqueue helpers for admin mutations.
enum AdminSyncEnqueue {

    static func enqueueUpdate(
        entityType: SyncEntityType,
        entityId: String,
        queue: SyncOperationRepository,
        now: Date
    ) async throws {
        let existing = try await queue.list(entityType: entityType, entityId: entityId)
        let version = (existing.map(\.localVersion).max() ?? 0) + 1
        let operation = try SyncOperation.pending(
            entityType: entityType,
            entityId: entityId,
            operationType: .update,
            createdAt: now,
            localVersion: version
        )
        _ = try await queue.enqueue(operation)
    }
}
