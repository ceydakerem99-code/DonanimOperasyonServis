import Foundation

/// Persistence surface for notes attached to a work order. Notes are
/// append-only from the Domain's perspective — edits should go
/// through an `EditRequest` for completed orders.
protocol WorkOrderNoteRepository: Sendable {
    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderNote]
    func save(_ note: WorkOrderNote) async throws
    func delete(id: String, for workOrderId: WorkOrderID) async throws
}
