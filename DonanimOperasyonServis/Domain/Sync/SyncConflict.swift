import Foundation

/// Documented resolution choices for a later `ConflictResolver`.
/// Phase 5A only names them; nothing applies `useLocal` / `useRemote`.
enum SyncConflictResolutionChoice: String, CaseIterable, Hashable, Sendable, Codable {
    case useLocal
    case useRemote
}

/// Lifecycle of a detected conflict. 5A only models `unresolved`;
/// applying a choice is a later phase (`ConflictResolver`).
enum SyncConflictStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case unresolved
}

/// A detected local/remote divergence that retry cannot fix.
///
/// Payloads are stored as references (same convention as
/// `SyncOperation.payloadReference`), not as blobs.
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
            status: .unresolved
        )
    }
}
