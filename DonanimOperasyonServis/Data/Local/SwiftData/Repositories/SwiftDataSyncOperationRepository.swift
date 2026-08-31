import Foundation

/// SwiftData-backed `SyncOperationRepository`. All storage work goes
/// through the shared `LocalPersistence` actor so concurrent
/// enqueue/update calls serialize on one `ModelContext`.
struct SwiftDataSyncOperationRepository: SyncOperationRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func enqueue(_ operation: SyncOperation) async throws -> SyncEnqueueOutcome {
        try await store.enqueueSyncOperation(operation)
    }

    func fetch(id: SyncOperationID) async throws -> SyncOperation {
        guard let operation = try await store.fetchSyncOperation(id: id.rawValue) else {
            throw DomainError.notFound(entity: "SyncOperation", id: id.rawValue)
        }
        return operation
    }

    func fetchPending(now: Date) async throws -> [SyncOperation] {
        try await store.fetchPendingSyncOperations(now: now)
    }

    func fetchInProgress() async throws -> [SyncOperation] {
        try await store.fetchSyncOperations(status: .inProgress)
    }

    func fetchFailed() async throws -> [SyncOperation] {
        try await store.fetchSyncOperations(status: .failed)
    }

    func fetchConflicts() async throws -> [SyncOperation] {
        try await store.fetchSyncOperations(status: .conflict)
    }

    func fetch(status: SyncStatus) async throws -> [SyncOperation] {
        try await store.fetchSyncOperations(status: status)
    }

    func update(_ operation: SyncOperation) async throws {
        try await store.updateSyncOperation(operation)
    }

    func delete(id: SyncOperationID) async throws {
        try await store.deleteSyncOperation(id: id.rawValue)
    }

    func deleteCompleted() async throws {
        try await store.deleteCompletedSyncOperations()
    }

    func deleteFailed(ids: [SyncOperationID]) async throws {
        try await store.deleteFailedSyncOperations(ids: ids.map(\.rawValue))
    }

    func countPending(now: Date) async throws -> Int {
        try await store.countPendingSyncOperations(now: now)
    }

    func prepareRetry(id: SyncOperationID) async throws {
        try await store.prepareSyncOperationRetry(id: id.rawValue)
    }

    func list(entityType: SyncEntityType, entityId: String) async throws -> [SyncOperation] {
        try await store.listSyncOperations(entityType: entityType.rawValue, entityId: entityId)
    }
}
