import Foundation

/// Applied choice stored on a resolved `SyncConflict`.
///
/// `unresolved` is not a stored choice — it is the absence of
/// `SyncConflict.resolution`. Callers pass
/// `ConflictResolutionDecision` (which includes `unresolved`) into
/// `ConflictResolver`.
enum SyncConflictResolutionChoice: String, CaseIterable, Hashable, Sendable, Codable {
    case useLocal
    case useRemote
}

/// Lifecycle token for a detected conflict row.
///
/// Intentionally a single case: resolution is recorded on
/// `resolution` / `resolvedAt` / `resolvedByUserId` rather than by
/// growing this enum. A row is open when `resolution == nil`.
enum SyncConflictStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case unresolved
}

/// A detected local/remote divergence that retry cannot fix.
///
/// Payloads are stored as references (same convention as
/// `SyncOperation.payloadReference`), not as blobs.
///
/// Detection-time snapshot fields (`localVersion`, `remoteVersion`,
/// `localReference`, `remoteReference`, `detectedAt`) are immutable
/// for audit: resolution only fills `resolution` metadata.
struct SyncConflict: Hashable, Sendable, Identifiable, Codable {
    let id: SyncConflictID
    var syncOperationId: SyncOperationID
    var entityType: SyncEntityType
    var entityId: String
    var localVersion: Int
    var remoteVersion: Int
    var localReference: String?
    var remoteReference: String?
    var detectedAt: Date
    var status: SyncConflictStatus
    /// `nil` while the conflict is open. `useLocal` / `useRemote`
    /// after a successful privileged resolve. Never physically deleted.
    var resolution: SyncConflictResolutionChoice?
    var resolvedAt: Date?
    var resolvedByUserId: UserID?

    var isResolved: Bool { resolution != nil }

    static func unresolved(
        id: SyncConflictID = SyncConflictID(UUID().uuidString),
        syncOperationId: SyncOperationID,
        entityType: SyncEntityType,
        entityId: String,
        localVersion: Int,
        remoteVersion: Int,
        localReference: String? = nil,
        remoteReference: String? = nil,
        detectedAt: Date
    ) -> SyncConflict {
        SyncConflict(
            id: id,
            syncOperationId: syncOperationId,
            entityType: entityType,
            entityId: entityId,
            localVersion: localVersion,
            remoteVersion: remoteVersion,
            localReference: localReference,
            remoteReference: remoteReference,
            detectedAt: detectedAt,
            status: .unresolved,
            resolution: nil,
            resolvedAt: nil,
            resolvedByUserId: nil
        )
    }

    /// Returns a copy with resolution metadata set. Snapshot fields
    /// (versions, references, `detectedAt`) are preserved.
    func markingResolved(
        choice: SyncConflictResolutionChoice,
        at date: Date,
        by userId: UserID
    ) -> SyncConflict {
        var resolved = self
        resolved.resolution = choice
        resolved.resolvedAt = date
        resolved.resolvedByUserId = userId
        return resolved
    }
}
