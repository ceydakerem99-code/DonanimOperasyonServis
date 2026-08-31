import Foundation

/// Admin-facing application dependencies wired from `DIContainer`.
struct AdminDependencies: Sendable {
    let listUsers: ListUsersUseCase
    let getUser: GetUserUseCase
    let userService: AdminUserService
    let workOrderService: AdminWorkOrderService
    let localDirectoryCacheRefresh: LocalDirectoryCacheRefresh
    let getSystemWorkOrders: GetSystemWorkOrdersUseCase
    let getSystemWorkOrder: GetSystemWorkOrderUseCase
    let userRepository: UserRepository
    let customerRepository: CustomerRepository
    let workOrderNoteRepository: WorkOrderNoteRepository
    let workOrderPhotoRepository: WorkOrderPhotoRepository
    let workOrderLocationRepository: WorkOrderLocationRepository
    let statusHistoryRepository: WorkOrderStatusHistoryRepository
    let signatureRepository: SignatureRepository
    let editRequestRepository: EditRequestRepository
    let customerSatisfactionRepository: any CustomerSatisfactionRepository
    let notificationRepository: NotificationRepository
    let syncOperationRepository: SyncOperationRepository
    let syncConflictRepository: SyncConflictRepository
    let syncManager: any SyncManaging
    let networkReachability: NetworkReachabilityProviding
    let profileAccountService: ProfileAccountService
    let storageDataSource: any FirebaseStorageDataSource
}

extension DIContainer {
    func makeAdminDependencies() -> AdminDependencies {
        let authAccounts: any AuthAccountCreating
        if firebaseBootstrapOutcome == .configured
            || firebaseBootstrapOutcome == .alreadyConfigured
        {
            authAccounts = LiveIdentityToolkitAuthAccountCreator()
        } else {
            authAccounts = FakeAuthAccountCreator()
        }

        return AdminDependencies(
            listUsers: ListUsersUseCase(userRepository: userRepository),
            getUser: GetUserUseCase(userRepository: userRepository),
            userService: AdminUserService(
                updateUser: UpdateUserUseCase(userRepository: userRepository),
                createUserUseCase: CreateUserUseCase(
                    userRepository: userRepository,
                    authAccounts: authAccounts
                ),
                remoteUsers: remoteUserRepository,
                syncOperationRepository: syncOperationRepository,
                networkReachability: networkReachability
            ),
            workOrderService: AdminWorkOrderService(
                deleteWorkOrder: DeleteWorkOrderUseCase(workOrderRepository: workOrderRepository),
                workOrderRepository: workOrderRepository,
                syncOperationRepository: syncOperationRepository
            ),
            localDirectoryCacheRefresh: localDirectoryCacheRefresh,
            getSystemWorkOrders: GetSystemWorkOrdersUseCase(workOrderRepository: workOrderRepository),
            getSystemWorkOrder: GetSystemWorkOrderUseCase(workOrderRepository: workOrderRepository),
            userRepository: userRepository,
            customerRepository: customerRepository,
            workOrderNoteRepository: workOrderNoteRepository,
            workOrderPhotoRepository: workOrderPhotoRepository,
            workOrderLocationRepository: workOrderLocationRepository,
            statusHistoryRepository: workOrderStatusHistoryRepository,
            signatureRepository: signatureRepository,
            editRequestRepository: editRequestRepository,
            customerSatisfactionRepository: customerSatisfactionRepository,
            notificationRepository: notificationRepository,
            syncOperationRepository: syncOperationRepository,
            syncConflictRepository: syncConflictRepository,
            syncManager: syncManager,
            networkReachability: networkReachability,
            profileAccountService: makeProfileAccountService(),
            storageDataSource: firebaseStorageDataSource
        )
    }
}
