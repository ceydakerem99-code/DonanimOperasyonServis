import Foundation

/// Sequential local-queue → remote-repository executor.
///
/// An `actor` so two `sync(operation:)` calls on the same instance
/// cannot interleave: the second caller observes `inProgress` /
/// `succeeded` / `conflict` and does not hit remote again.
///
/// Local business entities are never overwritten with a remote
/// response (Phase 5D reconciliation). Only the `SyncOperation`
/// row (and an optional `SyncConflict` row) is updated.
actor LocalToRemoteSyncManager: SyncManaging {

    private let queue: any SyncOperationRepository
    private let conflicts: any SyncConflictRepository
    private let local: SyncEntityRepositories
    private let remote: SyncEntityRepositories
    /// Guards re-entrant `await` points so the same `id` cannot be
    /// dispatched twice on this instance.
    private var inFlightIDs: Set<String> = []

    init(
        queue: any SyncOperationRepository,
        conflicts: any SyncConflictRepository,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) {
        self.queue = queue
        self.conflicts = conflicts
        self.local = local
        self.remote = remote
    }

    func syncPending(now: Date) async throws {
        let pending = try await queue.fetchPending(now: now)
        for operation in pending {
            try await sync(operation: operation, now: now)
        }
    }

    func sync(operation: SyncOperation, now: Date) async throws {
        let rawID = operation.id.rawValue
        guard !inFlightIDs.contains(rawID) else { return }
        inFlightIDs.insert(rawID)
        defer { inFlightIDs.remove(rawID) }

        let latest = try await queue.fetch(id: operation.id)

        if try await shouldHoldForUnresolvedOrAbandonedConflict(latest) {
            return
        }

        switch latest.status {
        case .inProgress, .succeeded, .conflict:
            return
        case .failed:
            try await queue.prepareRetry(id: latest.id)
        case .pending:
            break
        }

        var running = try await queue.fetch(id: operation.id)
        running.status = .inProgress
        running.lastAttemptAt = now
        running.updatedAt = now
        try await queue.update(running)
        running = try await queue.fetch(id: operation.id)

        do {
            try await SyncRemoteDispatcher.apply(
                operation: running,
                local: local,
                remote: remote
            )
            try await markSucceeded(running, now: now)
        } catch let signal as SyncConflictDetected {
            try await markConflict(running, signal: signal, now: now)
        } catch {
            let syncError = SyncErrorMapping.from(error)
            if syncError == .conflict {
                try await markConflict(
                    running,
                    signal: SyncConflictDetected(
                        localVersion: running.localVersion,
                        remoteVersion: running.remoteVersion,
                        localReference: running.payloadReference,
                        remoteReference: nil
                    ),
                    now: now
                )
            } else {
                try await markFailed(running, error: syncError, now: now)
            }
        }
    }

    // MARK: - Outcomes

    /// An unresolved conflict, or a `useRemote` resolution that
    /// abandoned the local mutation, must not be pushed again.
    /// `useLocal` lifts the hold so the existing state machine can
    /// continue (pending/failed rows) or a newly enqueued row can run.
    private func shouldHoldForUnresolvedOrAbandonedConflict(
        _ operation: SyncOperation
    ) async throws -> Bool {
        guard let conflict = try await conflicts.fetch(syncOperationId: operation.id) else {
            return false
        }
        switch conflict.resolution {
        case nil:
            return true
        case .useRemote:
            return true
        case .useLocal:
            return false
        }
    }

    private func markSucceeded(_ operation: SyncOperation, now: Date) async throws {
        var done = operation
        done.status = .succeeded
        done.lastAttemptAt = now
        done.nextRetryAt = nil
        done.errorMessage = nil
        done.updatedAt = now
        try await queue.update(done)
    }

    private func markFailed(
        _ operation: SyncOperation,
        error: SyncError,
        now: Date
    ) async throws {
        var failed = operation
        let recorded = failed.retryCount
        failed.retryCount = recorded + 1
        failed.status = .failed
        failed.lastAttemptAt = now
        failed.nextRetryAt = SyncRetryPolicy.nextRetryDate(
            error: error,
            retryCount: recorded,
            now: now
        )
        failed.errorMessage = error.diagnosticMessage
        failed.updatedAt = now
        try await queue.update(failed)
    }

    private func markConflict(
        _ operation: SyncOperation,
        signal: SyncConflictDetected,
        now: Date
    ) async throws {
        let record = SyncConflict.unresolved(
            syncOperationId: operation.id,
            entityType: operation.entityType,
            entityId: operation.entityId,
            localVersion: signal.localVersion,
            remoteVersion: signal.remoteVersion,
            localReference: signal.localReference,
            remoteReference: signal.remoteReference,
            detectedAt: now
        )
        try await conflicts.save(record)

        var conflicted = operation
        conflicted.status = .conflict
        conflicted.lastAttemptAt = now
        conflicted.nextRetryAt = nil
        conflicted.errorMessage = SyncError.conflict.diagnosticMessage
        conflicted.updatedAt = now
        try await queue.update(conflicted)
    }
}
