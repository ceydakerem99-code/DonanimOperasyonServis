import Foundation

/// SwiftData-backed implementation of `WorkOrderLocationRepository`.
struct SwiftDataWorkOrderLocationRepository: WorkOrderLocationRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderLocation] {
        try await store.listLocations(workOrderId: workOrderId.rawValue)
    }

    func save(_ location: WorkOrderLocation) async throws {
        try await store.insertLocation(location)
    }
}
