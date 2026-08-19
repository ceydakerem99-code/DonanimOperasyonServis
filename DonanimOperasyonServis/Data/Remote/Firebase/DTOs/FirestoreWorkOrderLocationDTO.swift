import Foundation

/// Firestore DTO for the `workOrderLocations` collection.
///
/// `LocationCoordinate` is flattened to three scalars
/// (`latitude`, `longitude`, `accuracy`) so we don't have to hoist
/// Firestore's `GeoPoint` type into the Domain-agnostic DTO layer.
/// GeoPoint could be adopted later without changing the Domain
/// surface.
struct FirestoreWorkOrderLocationDTO: Codable, Hashable, Sendable {
    let id: String
    let workOrderId: String
    let event: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let capturedByUserId: String
    let capturedAt: Date
}

extension FirestoreWorkOrderLocationDTO {

    init(domain: WorkOrderLocation) {
        self.id = domain.id
        self.workOrderId = domain.workOrderId.rawValue
        self.event = domain.event.rawValue
        self.latitude = domain.coordinate.latitude
        self.longitude = domain.coordinate.longitude
        self.accuracy = domain.coordinate.accuracy
        self.capturedByUserId = domain.capturedByUserId.rawValue
        self.capturedAt = domain.capturedAt
    }

    func toDomain() -> WorkOrderLocation? {
        guard let resolvedEvent = LocationEvent(rawValue: event) else { return nil }
        return WorkOrderLocation(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            event: resolvedEvent,
            coordinate: LocationCoordinate(
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy
            ),
            capturedByUserId: UserID(capturedByUserId),
            capturedAt: capturedAt
        )
    }
}
