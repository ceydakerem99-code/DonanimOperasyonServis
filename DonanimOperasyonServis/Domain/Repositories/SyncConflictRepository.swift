import Foundation

/// Local persistence for detected `SyncConflict` records.
///
/// Conflicts are first-class rows, not a JSON blob on
/// `SyncOperation`. Rows are never physically deleted; resolution
/// is recorded as metadata (`resolution`, `resolvedAt`,
/// `resolvedByUserId`). `listUnresolved()` returns open rows only.
protocol SyncConflictRepository: Sendable {
    func save(_ conflict: SyncConflict) async throws
    func fetch(id: SyncConflictID) async throws -> SyncConflict
    func fetch(syncOperationId: SyncOperationID) async throws -> SyncConflict?
    func listUnresolved() async throws -> [SyncConflict]
}
