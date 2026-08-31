import Foundation

/// Result of putting a `SyncOperation` on the local queue.
///
/// Duplicate detection is keyed **only** on `idempotencyKey`. The
/// existing row is returned as-is: no second insert, no silent
/// overwrite of status / payload / versions.
enum SyncEnqueueOutcome: Hashable, Sendable {
    /// First time this `idempotencyKey` is seen. The operation is now
    /// on the queue.
    case inserted(SyncOperation)
    /// A row with this `idempotencyKey` already exists. `existing` is
    /// the stored value, unchanged.
    case duplicate(existing: SyncOperation)
}

/// Local sync-queue surface. Implementations persist on-device
/// (SwiftData in Phase 5B). The protocol itself does not know about
/// SwiftData or Firebase — the queue is never a remote collection.
///
/// `fetchPending(now:)` is the "ready to send" query: `.pending`
/// rows whose `nextRetryAt` has elapsed (or is unset), plus `.failed`
/// rows whose backoff window has elapsed. Failed rows still waiting
/// on `nextRetryAt` are **not** pending.
protocol SyncOperationRepository: Sendable {
    func enqueue(_ operation: SyncOperation) async throws -> SyncEnqueueOutcome
    func fetch(id: SyncOperationID) async throws -> SyncOperation
    func fetchPending(now: Date) async throws -> [SyncOperation]
    func fetchInProgress() async throws -> [SyncOperation]
    func fetchFailed() async throws -> [SyncOperation]
    func fetchConflicts() async throws -> [SyncOperation]
    /// Every queue row with the given lifecycle status (read-only
    /// listing; does not apply retry/backoff eligibility rules).
    func fetch(status: SyncStatus) async throws -> [SyncOperation]
    func update(_ operation: SyncOperation) async throws
    /// Removes a single row. Only `.succeeded` operations may be
    /// deleted this way; any other status is rejected.
    func delete(id: SyncOperationID) async throws
    /// Bulk cleanup of `.succeeded` rows. Leaves pending / inProgress
    /// / failed / conflict untouched. No scheduler — callers decide
    /// when to run this.
    func deleteCompleted() async throws
    /// Removes `.failed` rows by id. Used to prune stale failures that
    /// a newer `.succeeded` mutation of the same entity has superseded.
    /// Any other status is rejected.
    func deleteFailed(ids: [SyncOperationID]) async throws
    func countPending(now: Date) async throws -> Int
    /// Moves a `.failed` row back to `.pending` so
    /// `SyncStatusStateMachine` can take `pending → inProgress`.
    /// This reset is **not** a state-machine transition (see
    /// `SyncStatus.isTerminal`). No-op when already `.pending`.
    func prepareRetry(id: SyncOperationID) async throws
    /// Every queue row for this entity, including succeeded.
    /// Reconciliation uses this to detect pending mutations without
    /// deleting anything.
    func list(entityType: SyncEntityType, entityId: String) async throws -> [SyncOperation]
}
