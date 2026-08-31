import Foundation

/// Classifies local queue rows for badge / cleanup without talking to Firebase.
///
/// A `.failed` row is stale only when a **newer** `.succeeded` row exists
/// for the same `(entityType, entityId)`. Permanent `unauthorized` rows
/// without a later success are kept — they may never have reached Firestore.
enum SyncQueueIssueClassifier {

    enum FailedKind: Equatable, Sendable {
        case retryable
        case permanent
    }

    static func isNewerSucceeded(
        _ succeeded: SyncOperation,
        thanFailed failed: SyncOperation
    ) -> Bool {
        guard succeeded.status == .succeeded,
              failed.status == .failed,
              succeeded.entityType == failed.entityType,
              succeeded.entityId == failed.entityId
        else {
            return false
        }
        if succeeded.localVersion != failed.localVersion {
            return succeeded.localVersion > failed.localVersion
        }
        return succeeded.createdAt > failed.createdAt
    }

    static func staleFailedIDs(
        failed: [SyncOperation],
        succeeded: [SyncOperation]
    ) -> [SyncOperationID] {
        let successes = succeeded.filter { $0.status == .succeeded }
        let succeededWorkOrderIDs = Set(
            successes
                .filter { $0.entityType == .workOrder }
                .map(\.entityId)
        )
        var ids: [SyncOperationID] = []
        var seen = Set<SyncOperationID>()
        for row in failed where row.status == .failed {
            let superseded = successes.contains { isNewerSucceeded($0, thanFailed: row) }
            let parentSynced = SyncPolicy.requiresWorkOrderPayloadReference(row.entityType)
                && row.payloadReference.map { succeededWorkOrderIDs.contains($0) } == true
            if superseded || parentSynced, seen.insert(row.id).inserted {
                ids.append(row.id)
            }
        }
        return ids
    }

    static func snapshot(
        failed: [SyncOperation],
        pending: [SyncOperation],
        succeeded: [SyncOperation],
        conflicts: [SyncOperation],
        at date: Date = Date()
    ) -> SyncIssueSnapshot {
        SyncIssueSnapshot(
            activeFailedCount: activeFailedCount(failed),
            retryableFailedCount: retryableFailedCount(failed),
            pendingCount: pending.filter { $0.status == .pending }.count,
            succeededCount: succeeded.filter { $0.status == .succeeded }.count,
            conflictCount: conflicts.filter { $0.status == .conflict }.count,
            updatedAt: date
        )
    }

    static func kind(ofFailed operation: SyncOperation) -> FailedKind? {
        guard operation.status == .failed else { return nil }
        if operation.nextRetryAt != nil {
            return .retryable
        }
        return .permanent
    }

    static func activeFailedCount(_ operations: [SyncOperation]) -> Int {
        operations.reduce(into: 0) { count, operation in
            if kind(ofFailed: operation) == .permanent {
                count += 1
            }
        }
    }

    static func retryableFailedCount(_ operations: [SyncOperation]) -> Int {
        operations.reduce(into: 0) { count, operation in
            if kind(ofFailed: operation) == .retryable {
                count += 1
            }
        }
    }
}
