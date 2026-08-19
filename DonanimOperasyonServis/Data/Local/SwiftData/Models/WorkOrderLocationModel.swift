import Foundation
import SwiftData

/// SwiftData persistence model for `WorkOrderLocation`.
/// `LocationCoordinate` is flattened into three scalar columns
/// (`latitude`, `longitude`, `accuracy`) so we don't pull in a
/// separate value-type attribute encoder.
@Model
final class WorkOrderLocationModel {

    @Attribute(.unique) var id: String

    var workOrder: WorkOrderModel?
    var workOrderId: String

    var eventRaw: String
    var latitude: Double
    var longitude: Double
    var accuracy: Double?
    var capturedByUserId: String
    var capturedAt: Date

    init(
        id: String,
        workOrderId: String,
        eventRaw: String,
        latitude: Double,
        longitude: Double,
        accuracy: Double?,
        capturedByUserId: String,
        capturedAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.eventRaw = eventRaw
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.capturedByUserId = capturedByUserId
        self.capturedAt = capturedAt
    }
}

extension WorkOrderLocationModel {

    convenience init(domain: WorkOrderLocation) {
        self.init(
            id: domain.id,
            workOrderId: domain.workOrderId.rawValue,
            eventRaw: domain.event.rawValue,
            latitude: domain.coordinate.latitude,
            longitude: domain.coordinate.longitude,
            accuracy: domain.coordinate.accuracy,
            capturedByUserId: domain.capturedByUserId.rawValue,
            capturedAt: domain.capturedAt
        )
    }

    func toDomain() -> WorkOrderLocation? {
        guard let event = LocationEvent(rawValue: eventRaw) else { return nil }
        return WorkOrderLocation(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            event: event,
            coordinate: LocationCoordinate(latitude: latitude, longitude: longitude, accuracy: accuracy),
            capturedByUserId: UserID(capturedByUserId),
            capturedAt: capturedAt
        )
    }
}
