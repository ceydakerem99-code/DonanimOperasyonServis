import Foundation

/// Operator-facing application dependencies wired from `DIContainer`.
struct OperatorDependencies: Sendable {
    let getWorkOrders: GetWorkOrdersUseCase
    let getWorkOrder: GetWorkOrderUseCase
    let workOrderService: OperatorWorkOrderService
    let customerRepository: CustomerRepository
    let userRepository: UserRepository
    let workOrderNoteRepository: WorkOrderNoteRepository
    let statusHistoryRepository: WorkOrderStatusHistoryRepository
    let editRequestRepository: EditRequestRepository
    let approveEditRequest: ApproveEditRequestUseCase
    let rejectEditRequest: RejectEditRequestUseCase
    let notificationRepository: NotificationRepository
    let syncOperationRepository: SyncOperationRepository
    let networkReachability: NetworkReachabilityProviding
}

extension DIContainer {
    func makeOperatorDependencies() -> OperatorDependencies {
        OperatorDependencies(
            getWorkOrders: GetWorkOrdersUseCase(workOrderRepository: workOrderRepository),
            getWorkOrder: GetWorkOrderUseCase(workOrderRepository: workOrderRepository),
            workOrderService: OperatorWorkOrderService(
                createWorkOrder: CreateWorkOrderUseCase(
                    workOrderRepository: workOrderRepository,
                    statusHistoryRepository: workOrderStatusHistoryRepository
                ),
                statusHistoryRepository: workOrderStatusHistoryRepository,
                syncOperationRepository: syncOperationRepository
            ),
            customerRepository: customerRepository,
            userRepository: userRepository,
            workOrderNoteRepository: workOrderNoteRepository,
            statusHistoryRepository: workOrderStatusHistoryRepository,
            editRequestRepository: editRequestRepository,
            approveEditRequest: ApproveEditRequestUseCase(
                editRequestRepository: editRequestRepository,
                workOrderRepository: workOrderRepository
            ),
            rejectEditRequest: RejectEditRequestUseCase(
                editRequestRepository: editRequestRepository
            ),
            notificationRepository: notificationRepository,
            syncOperationRepository: syncOperationRepository,
            networkReachability: networkReachability
        )
    }
}
