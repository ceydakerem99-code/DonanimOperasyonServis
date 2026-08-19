import Foundation

/// Persistence surface for `EditRequest` records. Queries are
/// scoped by work order (technician view: "my edit requests for
/// this order") and by status (operator inbox: "pending requests").
protocol EditRequestRepository: Sendable {
    func fetch(id: EditRequestID) async throws -> EditRequest
    func list(for workOrderId: WorkOrderID) async throws -> [EditRequest]
    func listByStatus(_ status: EditRequestStatus) async throws -> [EditRequest]
    func save(_ request: EditRequest) async throws
}
