import Foundation

/// SwiftData-backed implementation of `WorkOrderRepository`.
///
/// Filtering is currently done in-memory in `LocalPersistence`. That
/// is acceptable at v3 scale (single-user offline store), but is the
/// obvious first hot-spot to replace with proper SwiftData
/// predicates once the dataset grows or a Firestore mirror lands.
struct SwiftDataWorkOrderRepository: WorkOrderRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func fetch(id: WorkOrderID) async throws -> WorkOrder {
        guard let order = try await store.fetchWorkOrder(id: id.rawValue) else {
            throw DomainError.notFound(entity: "WorkOrder", id: id.rawValue)
        }
        return order
    }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        try await store.listWorkOrders(filter: filter)
    }

    func save(_ workOrder: WorkOrder) async throws {
        try await store.upsertWorkOrder(workOrder)
    }

    func delete(id: WorkOrderID) async throws {
        try await store.deleteWorkOrder(id: id.rawValue)
    }
}
