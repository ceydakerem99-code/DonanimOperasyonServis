import Foundation

/// SwiftData-backed `SyncConflictRepository`. Delegates to the
/// shared `LocalPersistence` actor.
struct SwiftDataSyncConflictRepository: SyncConflictRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func save(_ conflict: SyncConflict) async throws {
        try await store.upsertSyncConflict(conflict)
    }

    func fetch(id: SyncConflictID) async throws -> SyncConflict {
        guard let conflict = try await store.fetchSyncConflict(id: id.rawValue) else {
            throw DomainError.notFound(entity: "SyncConflict", id: id.rawValue)
        }
        return conflict
    }

    func fetch(syncOperationId: SyncOperationID) async throws -> SyncConflict? {
        try await store.fetchSyncConflict(syncOperationId: syncOperationId.rawValue)
    }

    func listUnresolved() async throws -> [SyncConflict] {
        try await store.listUnresolvedSyncConflicts()
    }
}
