import Foundation

/// Persistence surface for photo metadata associated with a work
/// order. The binary content itself is managed by a separate storage
/// service (added in later phases).
protocol WorkOrderPhotoRepository: Sendable {
    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderPhoto]
    func save(_ photo: WorkOrderPhoto) async throws
    func delete(id: String, for workOrderId: WorkOrderID) async throws
}
