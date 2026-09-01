import Foundation

struct TechnicianDependencies: Sendable {
    let getWorkOrders: GetWorkOrdersUseCase
    let getWorkOrder: GetWorkOrderUseCase
    let workOrderService: TechnicianWorkOrderService
    let customerRepository: CustomerRepository
    let localDirectoryCacheRefresh: LocalDirectoryCacheRefresh
    let workOrderNoteRepository: WorkOrderNoteRepository
    let workOrderPhotoRepository: WorkOrderPhotoRepository
    let workOrderLocationRepository: WorkOrderLocationRepository
    let signatureRepository: SignatureRepository
    let statusHistoryRepository: WorkOrderStatusHistoryRepository
    let notificationRepository: NotificationRepository
    let syncOperationRepository: SyncOperationRepository
    let syncConflictRepository: SyncConflictRepository
    let networkReachability: NetworkReachabilityProviding
    let editRequestRepository: EditRequestRepository
    let editRequestService: TechnicianEditRequestService
    let profileAccountService: ProfileAccountService
    let storageDataSource: any FirebaseStorageDataSource
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
                customerSatisfactionService: TechnicianCustomerSatisfactionService(
                    createCustomerSatisfaction: CreateCustomerSatisfactionUseCase(
                        workOrderRepository: workOrderRepository,
                        customerSatisfactionRepository: customerSatisfactionRepository
                    ),
                    syncOperationRepository: syncOperationRepository,
                    workOrderRepository: workOrderRepository,
                    customerRepository: customerRepository,
                    syncLifecycle: syncCoordinator,
                    remoteCustomerSatisfactionRepository: remoteCustomerSatisfactionRepository,
                    networkReachability: networkReachability
                ),
                syncOperationRepository: syncOperationRepository,
                storageDataSource: firebaseStorageDataSource
            ),
            customerRepository: customerRepository,
            localDirectoryCacheRefresh: localDirectoryCacheRefresh,
            workOrderNoteRepository: workOrderNoteRepository,
            workOrderPhotoRepository: workOrderPhotoRepository,
            workOrderLocationRepository: workOrderLocationRepository,
            signatureRepository: signatureRepository,
            statusHistoryRepository: workOrderStatusHistoryRepository,
            notificationRepository: notificationRepository,
            syncOperationRepository: syncOperationRepository,
            syncConflictRepository: syncConflictRepository,
            networkReachability: networkReachability,
            editRequestRepository: editRequestRepository,
            editRequestService: TechnicianEditRequestService(
                createEditRequest: CreateEditRequestUseCase(
                    workOrderRepository: workOrderRepository,
                    editRequestRepository: editRequestRepository
                ),
                workOrderRepository: workOrderRepository,
                notificationRepository: notificationRepository,
                syncOperationRepository: syncOperationRepository
            ),
            profileAccountService: makeProfileAccountService(),
            storageDataSource: firebaseStorageDataSource
        )
    }
}
