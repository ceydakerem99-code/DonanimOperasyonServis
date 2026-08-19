import Foundation

/// Application-layer coordinator for technician work-order mutations.
struct TechnicianWorkOrderService: Sendable {
    let updateStatus: UpdateWorkOrderStatusUseCase
    let completeWorkOrder: CompleteWorkOrderUseCase
    let addNoteUseCase: AddWorkOrderNoteUseCase
    let addPhotoUseCase: AddWorkOrderPhotoUseCase
    let captureLocationUseCase: CaptureWorkOrderLocationUseCase
    let captureSignatureUseCase: CaptureSignatureUseCase
    let statusHistoryRepository: WorkOrderStatusHistoryRepository
    let syncOperationRepository: SyncOperationRepository
    let storageDataSource: FirebaseStorageDataSource

    @discardableResult
    func transitionStatus(
        actor: User,
        orderId: WorkOrderID,
        newStatus: WorkOrderStatus,
        pauseReason: PauseReason? = nil,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        let order = try await updateStatus.execute(
            actor: actor,
            orderId: orderId,
            newStatus: newStatus,
            pauseReason: pauseReason,
            at: now
        )
        try await TechnicianSyncEnqueue.enqueueUpdate(
            entityType: .workOrder,
            entityId: order.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            workOrderStatus: order.status
        )
        let history = try await statusHistoryRepository.list(for: order.id)
        if let latest = history.last {
            try await TechnicianSyncEnqueue.enqueueCreate(
                entityType: .workOrderStatusHistory,
                entityId: latest.id,
                queue: syncOperationRepository,
                now: now
            )
        }
        return order
    }

    @discardableResult
    func complete(
        actor: User,
        orderId: WorkOrderID,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        let order = try await completeWorkOrder.execute(
            actor: actor,
            orderId: orderId,
            at: now
        )
        try await TechnicianSyncEnqueue.enqueueUpdate(
            entityType: .workOrder,
            entityId: order.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            workOrderStatus: .completed
        )
        let history = try await statusHistoryRepository.list(for: order.id)
        if let latest = history.last {
            try await TechnicianSyncEnqueue.enqueueCreate(
                entityType: .workOrderStatusHistory,
                entityId: latest.id,
                queue: syncOperationRepository,
                now: now
            )
        }
        return order
    }

    @discardableResult
    func addNote(
        actor: User,
        orderId: WorkOrderID,
        text: String,
        at now: Date = Date()
    ) async throws -> WorkOrderNote {
        let note = try await addNoteUseCase.execute(
            actor: actor,
            orderId: orderId,
            text: text,
            at: now
        )
        try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .workOrderNote,
            entityId: note.id,
            queue: syncOperationRepository,
            now: now
        )
        return note
    }

    @discardableResult
    func addPhoto(
        actor: User,
        orderId: WorkOrderID,
        category: PhotoCategory,
        imageData: Data,
        photoId: String = UUID().uuidString,
        at now: Date = Date()
    ) async throws -> WorkOrderPhoto {
        let path = FirebaseStoragePath.photo(workOrderId: orderId, photoId: photoId)
        let storagePath: String?
        if await uploadIfPossible(data: imageData, to: path) {
            storagePath = path.rawValue
        } else {
            storagePath = "pending://\(path.rawValue)"
        }
        let photo = try await addPhotoUseCase.execute(
            actor: actor,
            orderId: orderId,
            category: category,
            storagePath: storagePath,
            photoId: photoId,
            at: now
        )
        try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .workOrderPhoto,
            entityId: photo.id,
            queue: syncOperationRepository,
            now: now
        )
        return photo
    }

    @discardableResult
    func recordLocation(
        actor: User,
        orderId: WorkOrderID,
        event: LocationEvent,
        coordinate: LocationCoordinate,
        at now: Date = Date()
    ) async throws -> WorkOrderLocation {
        let location = try await captureLocationUseCase.execute(
            actor: actor,
            orderId: orderId,
            event: event,
            coordinate: coordinate,
            at: now
        )
        try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .workOrderLocation,
            entityId: location.id,
            queue: syncOperationRepository,
            now: now
        )
        return location
    }

    @discardableResult
    func recordSignature(
        actor: User,
        orderId: WorkOrderID,
        kind: SignatureKind,
        imageData: Data,
        signerName: String? = nil,
        signatureId: String = UUID().uuidString,
        at now: Date = Date()
    ) async throws -> Signature {
        let path = FirebaseStoragePath.signature(workOrderId: orderId, signatureId: signatureId)
        let storagePath: String?
        if await uploadIfPossible(data: imageData, to: path) {
            storagePath = path.rawValue
        } else {
            storagePath = "pending://\(path.rawValue)"
        }
        let signature = try await captureSignatureUseCase.execute(
            actor: actor,
            orderId: orderId,
            kind: kind,
            storagePath: storagePath,
            signerName: signerName,
            signatureId: signatureId,
            at: now
        )
        try await TechnicianSyncEnqueue.enqueueCreate(
            entityType: .signature,
            entityId: signature.id,
            queue: syncOperationRepository,
            now: now
        )
        return signature
    }

    private func uploadIfPossible(data: Data, to path: FirebaseStoragePath) async -> Bool {
        do {
            _ = try await storageDataSource.upload(data: data, to: path)
            return true
        } catch {
            return false
        }
    }
}
