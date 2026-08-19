import Foundation

/// Admin-facing application dependencies wired from `DIContainer`.
struct AdminDependencies: Sendable {
    let listUsers: ListUsersUseCase
    let getUser: GetUserUseCase
    let userService: AdminUserService
    let getSystemWorkOrders: GetSystemWorkOrdersUseCase
    let getSystemWorkOrder: GetSystemWorkOrderUseCase
    let userRepository: UserRepository
    let customerRepository: CustomerRepository
    let workOrderNoteRepository: WorkOrderNoteRepository
    let workOrderPhotoRepository: WorkOrderPhotoRepository
    let signatureRepository: SignatureRepository
    let notificationRepository: NotificationRepository
    let syncOperationRepository: SyncOperationRepository
    let syncConflictRepository: SyncConflictRepository
    let networkReachability: NetworkReachabilityProviding
}

extension DIContainer {
    func makeAdminDependencies() -> AdminDependencies {
        AdminDependencies(
            listUsers: ListUsersUseCase(userRepository: userRepository),
            getUser: GetUserUseCase(userRepository: userRepository),
            userService: AdminUserService(
                updateUser: UpdateUserUseCase(userRepository: userRepository),
                syncOperationRepository: syncOperationRepository
            ),
            getSystemWorkOrders: GetSystemWorkOrdersUseCase(workOrderRepository: workOrderRepository),
            getSystemWorkOrder: GetSystemWorkOrderUseCase(workOrderRepository: workOrderRepository),
            userRepository: userRepository,
            customerRepository: customerRepository,
            workOrderNoteRepository: workOrderNoteRepository,
            workOrderPhotoRepository: workOrderPhotoRepository,
            signatureRepository: signatureRepository,
            notificationRepository: notificationRepository,
            syncOperationRepository: syncOperationRepository,
            syncConflictRepository: syncConflictRepository,
            networkReachability: networkReachability
        )
    }
}
