import Foundation

/// A GPS sample captured during work-order execution. One sample per
/// meaningful field event (`enRoute`, `arrived`, `completed`).
/// Consumed by `CompletionRequirements` to verify that mandatory
/// location evidence has been recorded.
struct WorkOrderLocation: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let workOrderId: WorkOrderID
    let event: LocationEvent
    let coordinate: LocationCoordinate
    let capturedByUserId: UserID
    let capturedAt: Date

    init(
        id: String,
        workOrderId: WorkOrderID,
        event: LocationEvent,
        coordinate: LocationCoordinate,
        capturedByUserId: UserID,
        capturedAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.event = event
        self.coordinate = coordinate
        self.capturedByUserId = capturedByUserId
        self.capturedAt = capturedAt
    }
}
