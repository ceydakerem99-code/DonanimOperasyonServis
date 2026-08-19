import Foundation

/// Persistence surface for the audit trail of status transitions on
/// a work order. Append-only; entries are immutable once written.
protocol WorkOrderStatusHistoryRepository: Sendable {
    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderStatusHistory]
    func append(_ entry: WorkOrderStatusHistory) async throws
}
