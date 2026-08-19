import Foundation

struct TechnicianDependencies: Sendable {
    let getWorkOrders: GetWorkOrdersUseCase
    let getWorkOrder: GetWorkOrderUseCase
    let workOrderService: TechnicianWorkOrderService
    let customerRepository: CustomerRepository
    let workOrderNoteRepository: WorkOrderNoteRepository
    let workOrderPhotoRepository: WorkOrderPhotoRepository
    let workOrderLocationRepository: WorkOrderLocationRepository
    let signatureRepository: SignatureRepository
    let statusHistoryRepository: WorkOrderStatusHistoryRepository
    let notificationRepository: NotificationRepository
    let syncOperationRepository: SyncOperationRepository
    let syncConflictRepository: SyncConflictRepository
    let networkReachability: NetworkReachabilityProviding
    let createEditRequest: CreateEditRequestUseCase
}

extension DIContainer {
    func makeTechnicianDependencies() -> TechnicianDependencies {
        TechnicianDependencies(
            getWorkOrders: GetWorkOrdersUseCase(workOrderRepository: workOrderRepository),
            getWorkOrder: GetWorkOrderUseCase(workOrderRepository: workOrderRepository),
            workOrderService: TechnicianWorkOrderService(
                updateStatus: UpdateWorkOrderStatusUseCase(
                    workOrderRepository: workOrderRepository,
                    statusHistoryRepository: workOrderStatusHistoryRepository
                ),
                completeWorkOrder: CompleteWorkOrderUseCase(
                    workOrderRepository: workOrderRepository,
                    statusHistoryRepository: workOrderStatusHistoryRepository,
                    noteRepository: workOrderNoteRepository,
                    photoRepository: workOrderPhotoRepository,
                    locationRepository: workOrderLocationRepository,
                    signatureRepository: signatureRepository
                ),
                addNoteUseCase: AddWorkOrderNoteUseCase(
                    workOrderRepository: workOrderRepository,
                    noteRepository: workOrderNoteRepository
                ),
                addPhotoUseCase: AddWorkOrderPhotoUseCase(
                    workOrderRepository: workOrderRepository,
                    photoRepository: workOrderPhotoRepository
                ),
                captureLocationUseCase: CaptureWorkOrderLocationUseCase(
                    workOrderRepository: workOrderRepository,
                    locationRepository: workOrderLocationRepository
                ),
                captureSignatureUseCase: CaptureSignatureUseCase(
                    workOrderRepository: workOrderRepository,
                    signatureRepository: signatureRepository
                ),
                statusHistoryRepository: workOrderStatusHistoryRepository,
                syncOperationRepository: syncOperationRepository,
                storageDataSource: firebaseStorageDataSource
            ),
            customerRepository: customerRepository,
            workOrderNoteRepository: workOrderNoteRepository,
            workOrderPhotoRepository: workOrderPhotoRepository,
            workOrderLocationRepository: workOrderLocationRepository,
            signatureRepository: signatureRepository,
            statusHistoryRepository: workOrderStatusHistoryRepository,
            notificationRepository: notificationRepository,
            syncOperationRepository: syncOperationRepository,
            syncConflictRepository: syncConflictRepository,
            networkReachability: networkReachability,
            createEditRequest: CreateEditRequestUseCase(
                workOrderRepository: workOrderRepository,
                editRequestRepository: editRequestRepository
            )
        )
    }
}
