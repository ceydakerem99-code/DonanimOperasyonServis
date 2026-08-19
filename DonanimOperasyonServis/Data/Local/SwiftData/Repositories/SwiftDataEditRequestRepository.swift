import Foundation

/// SwiftData-backed implementation of `EditRequestRepository`.
struct SwiftDataEditRequestRepository: EditRequestRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func fetch(id: EditRequestID) async throws -> EditRequest {
        guard let request = try await store.fetchEditRequest(id: id.rawValue) else {
            throw DomainError.notFound(entity: "EditRequest", id: id.rawValue)
        }
        return request
    }

    func list(for workOrderId: WorkOrderID) async throws -> [EditRequest] {
        try await store.listEditRequests(workOrderId: workOrderId.rawValue)
    }

    func listByStatus(_ status: EditRequestStatus) async throws -> [EditRequest] {
        try await store.listEditRequests(statusRaw: status.rawValue)
    }

    func save(_ request: EditRequest) async throws {
        try await store.upsertEditRequest(request)
    }
}
