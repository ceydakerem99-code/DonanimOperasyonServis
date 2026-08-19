import Foundation

/// Records a GPS sample for a work order assigned to the acting
/// technician.
struct CaptureWorkOrderLocationUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository
    let locationRepository: WorkOrderLocationRepository

    init(
        workOrderRepository: WorkOrderRepository,
        locationRepository: WorkOrderLocationRepository
    ) {
        self.workOrderRepository = workOrderRepository
        self.locationRepository = locationRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        event: LocationEvent,
        coordinate: LocationCoordinate,
        locationId: String = UUID().uuidString,
        at now: Date = Date()
    ) async throws -> WorkOrderLocation {
        guard RoleAccessPolicy.can(.captureLocationSample, as: actor.role) else {
            throw DomainError.unauthorized(action: .captureLocationSample)
        }

        let order = try await workOrderRepository.fetch(id: orderId)
        guard RoleAccessPolicy.canAct(on: order, as: actor) else {
            throw order.isLocked
                ? DomainError.workOrderLocked(order.id)
                : DomainError.unauthorized(action: .captureLocationSample)
        }

        let location = WorkOrderLocation(
            id: locationId,
            workOrderId: order.id,
            event: event,
            coordinate: coordinate,
            capturedByUserId: actor.id,
            capturedAt: now
        )
        try await locationRepository.save(location)
        return location
    }
}
