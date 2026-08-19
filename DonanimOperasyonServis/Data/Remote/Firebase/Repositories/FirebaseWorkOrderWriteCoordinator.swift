import Foundation

/// Persistence primitive that writes a `WorkOrder` together with
/// a `WorkOrderStatusHistory` entry in a single batch.
///
/// Domain remains the source of truth for *whether* a transition
/// is legal (`WorkOrderStateMachine`). This type only guarantees
/// that, once Domain has already produced both values, they land
/// in Firestore atomically.
struct FirebaseWorkOrderWriteCoordinator: Sendable {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func save(
        workOrder: WorkOrder,
        statusHistory: WorkOrderStatusHistory
    ) async throws {
        let writes = [
            FirestoreWrite.set(
                FirestoreWorkOrderDTO(domain: workOrder),
                collection: .workOrders,
                id: workOrder.id.rawValue
            ),
            FirestoreWrite.set(
                FirestoreWorkOrderStatusHistoryDTO(domain: statusHistory),
                collection: .workOrderStatusHistory,
                id: statusHistory.id
            )
        ]
        try await FirebaseRepositoryMapper.run(entity: "WorkOrder", id: workOrder.id.rawValue) {
            try await dataSource.commit(writes)
        }
    }
}
