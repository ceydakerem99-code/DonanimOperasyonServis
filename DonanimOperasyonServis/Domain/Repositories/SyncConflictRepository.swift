import Foundation

/// Local persistence for detected `SyncConflict` records.
///
/// Conflicts are first-class rows, not a JSON blob on
/// `SyncOperation`. Resolution (`useLocal` / `useRemote`) is a later
/// phase; this surface only stores and reads them.
protocol SyncConflictRepository: Sendable {
    func save(_ conflict: SyncConflict) async throws
    func fetch(id: SyncConflictID) async throws -> SyncConflict
    func fetch(syncOperationId: SyncOperationID) async throws -> SyncConflict?
    func listUnresolved() async throws -> [SyncConflict]
}
