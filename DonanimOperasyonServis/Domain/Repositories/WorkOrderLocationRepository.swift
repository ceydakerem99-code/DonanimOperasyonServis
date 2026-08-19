import Foundation

/// Persistence surface for GPS samples captured during work-order
/// execution. Append-only in v1.
protocol WorkOrderLocationRepository: Sendable {
    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderLocation]
    func save(_ location: WorkOrderLocation) async throws
}
