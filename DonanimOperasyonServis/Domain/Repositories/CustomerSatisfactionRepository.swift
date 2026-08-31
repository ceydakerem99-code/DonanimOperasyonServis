import Foundation

/// Persistence surface for `CustomerSatisfaction` records. Queries are
/// scoped by work order (per-order survey), by customer (aggregated
/// satisfaction history), and by status (pending/submitted/expired).
protocol CustomerSatisfactionRepository: Sendable {
    func fetch(id: CustomerSatisfactionID) async throws -> CustomerSatisfaction
    func list(for workOrderId: WorkOrderID) async throws -> [CustomerSatisfaction]
    func listByCustomer(_ customerId: CustomerID) async throws -> [CustomerSatisfaction]
    func listByStatus(_ status: CustomerSatisfactionStatus) async throws -> [CustomerSatisfaction]
    func save(_ satisfaction: CustomerSatisfaction) async throws
}
