import Foundation

/// Moves interrupted `.inProgress` rows to `.failed` using the
/// existing `SyncStatusStateMachine` (`inProgress → failed`) and
/// `SyncRetryPolicy` (treat as `.networkUnavailable` because the
/// remote outcome is unknown). Same `id` and `idempotencyKey`.
///
/// Does not call `SyncManager`, does not enqueue a second row, and
/// does not mark `.succeeded`.
actor LocalSyncRecoveryHandler: SyncRecoveryHandling {

    private let queue: any SyncOperationRepository

    init(queue: any SyncOperationRepository) {
        self.queue = queue
    }

    func recoverInterruptedOperations(now: Date) async throws -> SyncRecoveryOutcome {
        let interrupted = try await queue.fetchInProgress()
        var recovered: [SyncOperationID] = []
        for operation in interrupted {
            var row = operation
            let recorded = row.retryCount
            row.status = .failed
            row.retryCount = recorded + 1
            row.lastAttemptAt = now
            row.updatedAt = now
            row.errorMessage = SyncError.networkUnavailable.diagnosticMessage
            row.nextRetryAt = SyncRetryPolicy.nextRetryDate(
                error: .networkUnavailable,
                retryCount: recorded,
                now: now
            )
            try await queue.update(row)
            recovered.append(row.id)
        }
        return SyncRecoveryOutcome(recoveredOperationIDs: recovered)
    }
}
