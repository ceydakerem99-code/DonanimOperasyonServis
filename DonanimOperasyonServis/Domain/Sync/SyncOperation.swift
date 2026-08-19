import Foundation

/// A single outbound mutation waiting to be applied on the remote.
///
/// This is a Domain value. Persistence (`@Model`) lands in Phase 5B;
/// Firebase apply lands in Phase 5C. The queue never syncs itself
/// (`SyncEntityType` has no `syncOperation` case).
///
/// Versioning:
/// - `localVersion` is the local (SwiftData) revision of `entityId`
///   at enqueue time. It increases on every local mutation.
/// - `remoteVersion` is the last remote revision this device has
///   observed for that entity (`0` if never synced). Comparing the
///   two is how later phases detect stale applies and conflicts;
///   no optimistic-lock check is performed in 5A.
struct SyncOperation: Hashable, Sendable, Identifiable, Codable {
    let id: SyncOperationID
    var entityType: SyncEntityType
    var entityId: String
    var operationType: SyncOperationType
    /// Locator for the local record / serialized snapshot. Not the
    /// blob itself — storage of bytes is a Data-layer concern.
    var payloadReference: String?
    var createdAt: Date
    var updatedAt: Date
    var retryCount: Int
    var lastAttemptAt: Date?
    var nextRetryAt: Date?
    var status: SyncStatus
    var errorMessage: String?
    var localVersion: Int
    var remoteVersion: Int
    var idempotencyKey: SyncIdempotencyKey

    /// Builds a brand-new queue entry in `.pending`. Throws
    /// `SyncError.invalidPayload` when the identity fields are empty
    /// or `SyncPolicy` forbids the combination.
    static func pending(
        id: SyncOperationID = SyncOperationID(UUID().uuidString),
        entityType: SyncEntityType,
        entityId: String,
        operationType: SyncOperationType,
        payloadReference: String? = nil,
        createdAt: Date,
        localVersion: Int,
        remoteVersion: Int = 0,
        workOrderStatus: WorkOrderStatus? = nil,
        idempotencyKey: SyncIdempotencyKey? = nil
    ) throws -> SyncOperation {
        let trimmedId = entityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            throw SyncError.invalidPayload
        }
        guard SyncPolicy.canEnqueue(
            entityType: entityType,
            operationType: operationType,
            workOrderStatus: workOrderStatus
        ) else {
            throw SyncError.invalidPayload
        }
        let key = idempotencyKey ?? SyncIdempotencyKey.make(
            entityType: entityType,
            entityId: trimmedId,
            operationType: operationType,
            localVersion: localVersion
        )
        guard !key.rawValue.isEmpty else {
            throw SyncError.invalidPayload
        }
        return SyncOperation(
            id: id,
            entityType: entityType,
            entityId: trimmedId,
            operationType: operationType,
            payloadReference: payloadReference,
            createdAt: createdAt,
            updatedAt: createdAt,
            retryCount: 0,
            lastAttemptAt: nil,
            nextRetryAt: nil,
            status: .pending,
            errorMessage: nil,
            localVersion: localVersion,
            remoteVersion: remoteVersion,
            idempotencyKey: key
        )
    }
}
