import Foundation

/// Read-only snapshot shared by Technician / Operator / Admin report screens.
struct WorkOrderReportSnapshot: Equatable, Sendable {
    let workOrder: WorkOrder
    let customerName: String
    let customerAddress: String?
    let technicianName: String?
    let notes: [WorkOrderNote]
    let photos: [WorkOrderPhoto]
    let locations: [WorkOrderLocation]
    let signatures: [Signature]
    let timeline: [WorkOrderStatusHistory]
    var editRequests: [EditRequest] = []

    var noteCount: Int { notes.count }
    var photoCount: Int { photos.count }
    var locationCount: Int { locations.count }
    var signatureCount: Int { signatures.count }
    var editRequestCount: Int { editRequests.count }

    /// First occurrence time for a status transition (e.g. enRoute / arrived).
    func firstStatusTime(_ status: WorkOrderStatus) -> Date? {
        timeline.first(where: { $0.toStatus == status })?.occurredAt
    }

    /// First GPS capture time for a location event.
    func firstLocationTime(_ event: LocationEvent) -> Date? {
        locations
            .filter { $0.event == event }
            .map(\.capturedAt)
            .min()
    }

    /// Preferred display time: status history first, GPS fallback.
    func milestoneTime(status: WorkOrderStatus, locationEvent: LocationEvent?) -> Date? {
        if let statusTime = firstStatusTime(status) {
            return statusTime
        }
        if let locationEvent, let gpsTime = firstLocationTime(locationEvent) {
            return gpsTime
        }
        return nil
    }
}
