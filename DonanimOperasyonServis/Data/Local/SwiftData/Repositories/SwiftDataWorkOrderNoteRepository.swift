import Foundation

/// SwiftData-backed implementation of `WorkOrderNoteRepository`.
struct SwiftDataWorkOrderNoteRepository: WorkOrderNoteRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderNote] {
        try await store.listNotes(workOrderId: workOrderId.rawValue)
    }

    func save(_ note: WorkOrderNote) async throws {
        try await store.upsertNote(note)
    }

    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        _ = workOrderId  // Kept for API symmetry; note ids are globally unique.
        try await store.deleteNote(id: id)
    }
}
