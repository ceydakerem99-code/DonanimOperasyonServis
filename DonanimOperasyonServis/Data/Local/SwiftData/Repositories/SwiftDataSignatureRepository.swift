import Foundation

/// SwiftData-backed implementation of `SignatureRepository`.
struct SwiftDataSignatureRepository: SignatureRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func list(for workOrderId: WorkOrderID) async throws -> [Signature] {
        try await store.listSignatures(workOrderId: workOrderId.rawValue)
    }

    func save(_ signature: Signature) async throws {
        try await store.upsertSignature(signature)
    }

    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        _ = workOrderId
        try await store.deleteSignature(id: id)
    }
}
