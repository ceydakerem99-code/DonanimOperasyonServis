import Foundation

/// Attaches photo metadata to a non-completed work order assigned to
/// the acting technician.
struct AddWorkOrderPhotoUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository
    let photoRepository: WorkOrderPhotoRepository

    init(
        workOrderRepository: WorkOrderRepository,
        photoRepository: WorkOrderPhotoRepository
    ) {
        self.workOrderRepository = workOrderRepository
        self.photoRepository = photoRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        category: PhotoCategory,
        storagePath: String?,
        photoId: String = UUID().uuidString,
        at now: Date = Date()
    ) async throws -> WorkOrderPhoto {
        guard RoleAccessPolicy.can(.addWorkOrderPhoto, as: actor.role) else {
            throw DomainError.unauthorized(action: .addWorkOrderPhoto)
        }

        let order = try await workOrderRepository.fetch(id: orderId)
        guard RoleAccessPolicy.canAct(on: order, as: actor) else {
            throw order.isLocked
                ? DomainError.workOrderLocked(order.id)
                : DomainError.unauthorized(action: .addWorkOrderPhoto)
        }

        let photo = WorkOrderPhoto(
            id: photoId,
            workOrderId: order.id,
            category: category,
            storagePath: storagePath,
            capturedByUserId: actor.id,
            capturedAt: now
        )
        try await photoRepository.save(photo)
        return photo
    }
}
