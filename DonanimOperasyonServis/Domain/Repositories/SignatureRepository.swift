import Foundation

/// Persistence surface for signatures captured for a work order.
protocol SignatureRepository: Sendable {
    func list(for workOrderId: WorkOrderID) async throws -> [Signature]
    func save(_ signature: Signature) async throws
    func delete(id: String, for workOrderId: WorkOrderID) async throws
}
