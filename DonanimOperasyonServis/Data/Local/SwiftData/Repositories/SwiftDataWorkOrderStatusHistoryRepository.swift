import Foundation

/// SwiftData-backed implementation of
/// `WorkOrderStatusHistoryRepository`. History entries are
/// append-only from the Domain's perspective.
struct SwiftDataWorkOrderStatusHistoryRepository: WorkOrderStatusHistoryRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderStatusHistory] {
        try await store.listStatusHistory(workOrderId: workOrderId.rawValue)
    }

    func append(_ entry: WorkOrderStatusHistory) async throws {
        try await store.appendStatusHistory(entry)
    }
}
