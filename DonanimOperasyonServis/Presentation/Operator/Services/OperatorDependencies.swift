import Foundation

/// Operator-facing application dependencies wired from `DIContainer`.
struct OperatorDependencies: Sendable {
    let getWorkOrders: GetWorkOrdersUseCase
    let getWorkOrder: GetWorkOrderUseCase
    let workOrderService: OperatorWorkOrderService
    let customerService: OperatorCustomerService
    let workOrderTemplateService: OperatorWorkOrderTemplateService
    let customerRepository: CustomerRepository
    let userRepository: UserRepository
    let localDirectoryCacheRefresh: LocalDirectoryCacheRefresh
    let workOrderNoteRepository: WorkOrderNoteRepository
    let workOrderPhotoRepository: WorkOrderPhotoRepository
    let workOrderLocationRepository: WorkOrderLocationRepository
    let signatureRepository: SignatureRepository
    let statusHistoryRepository: WorkOrderStatusHistoryRepository
    let editRequestRepository: EditRequestRepository
    let editRequestService: OperatorEditRequestService
    let customerSatisfactionRepository: any CustomerSatisfactionRepository
    let customerSatisfactionService: OperatorCustomerSatisfactionService
    let notificationRepository: NotificationRepository
    let syncOperationRepository: SyncOperationRepository
    let syncConflictRepository: SyncConflictRepository
    let conflictResolver: any ConflictResolving
    let networkReachability: NetworkReachabilityProviding
    let profileAccountService: ProfileAccountService
    let storageDataSource: any FirebaseStorageDataSource
}

extension DIContainer {
    func makeProfileAccountService() -> ProfileAccountService {
        ProfileAccountService(
            changePasswordUseCase: ChangePasswordUseCase(
                authRepository: authRepository,
                networkReachability: networkReachability
            ),
            updateNotificationPreferencesUseCase: UpdateNotificationPreferencesUseCase(
                userRepository: userRepository
            ),
            userRepository: userRepository,
            syncOperationRepository: syncOperationRepository,
            networkReachability: networkReachability
        )
    }

    func makeOperatorDependencies() -> OperatorDependencies {
        OperatorDependencies(
            getWorkOrders: GetWorkOrdersUseCase(workOrderRepository: workOrderRepository),
            getWorkOrder: GetWorkOrderUseCase(workOrderRepository: workOrderRepository),
            workOrderService: OperatorWorkOrderService(
                createWorkOrder: CreateWorkOrderUseCase(
                    workOrderRepository: workOrderRepository,
                    statusHistoryRepository: workOrderStatusHistoryRepository
                ),
            assignWorkOrder: AssignWorkOrderUseCase(
                workOrderRepository: workOrderRepository
            ),
            updateWorkOrderPlanning: UpdateWorkOrderPlanningUseCase(
                workOrderRepository: workOrderRepository
            ),
            statusHistoryRepository: workOrderStatusHistoryRepository,
                syncOperationRepository: syncOperationRepository,
                notificationRepository: notificationRepository,
                realtimeWorkOrderCreate: realtimeCoordinator,
                syncLifecycle: syncCoordinator
            ),
            customerService: OperatorCustomerService(
                createCustomer: CreateCustomerUseCase(customerRepository: customerRepository),
                updateCustomer: UpdateCustomerUseCase(customerRepository: customerRepository),
                syncOperationRepository: syncOperationRepository,
                realtimeCustomerCreate: realtimeCoordinator
            ),
            workOrderTemplateService: OperatorWorkOrderTemplateService(
                repository: workOrderTemplateRepository
            ),
            customerRepository: customerRepository,
            userRepository: userRepository,
            localDirectoryCacheRefresh: localDirectoryCacheRefresh,
            workOrderNoteRepository: workOrderNoteRepository,
            workOrderPhotoRepository: workOrderPhotoRepository,
            workOrderLocationRepository: workOrderLocationRepository,
            signatureRepository: signatureRepository,
            statusHistoryRepository: workOrderStatusHistoryRepository,
            editRequestRepository: editRequestRepository,
            editRequestService: OperatorEditRequestService(
                approveEditRequest: ApproveEditRequestUseCase(
                    editRequestRepository: editRequestRepository,
                    workOrderRepository: workOrderRepository
                ),
                rejectEditRequest: RejectEditRequestUseCase(
                    editRequestRepository: editRequestRepository
                ),
                syncOperationRepository: syncOperationRepository
            ),
            customerSatisfactionRepository: customerSatisfactionRepository,
            customerSatisfactionService: OperatorCustomerSatisfactionService(
                createCustomerSatisfaction: CreateCustomerSatisfactionUseCase(
                    workOrderRepository: workOrderRepository,
                    customerSatisfactionRepository: customerSatisfactionRepository
                ),
                submitCustomerSatisfaction: SubmitCustomerSatisfactionUseCase(
                    customerSatisfactionRepository: customerSatisfactionRepository
                ),
                workOrderRepository: workOrderRepository,
                syncOperationRepository: syncOperationRepository
            ),
            notificationRepository: notificationRepository,
            syncOperationRepository: syncOperationRepository,
            syncConflictRepository: syncConflictRepository,
            conflictResolver: conflictResolver,
            networkReachability: networkReachability,
            profileAccountService: makeProfileAccountService(),
            storageDataSource: firebaseStorageDataSource
        )
    }
}
