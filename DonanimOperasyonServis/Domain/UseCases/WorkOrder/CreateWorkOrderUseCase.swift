import Foundation

/// Input payload for `CreateWorkOrderUseCase`. Kept separate from
/// `WorkOrder` itself so callers do not have to fill in derived
/// server-managed fields (`status`, `createdAt`, `updatedAt`,
/// `completedAt`).
struct NewWorkOrderRequest: Hashable, Sendable {
    let id: WorkOrderID
    let workOrderNumber: String
    let assignedTechnicianId: UserID
    let customerId: CustomerID
    let workType: WorkType
    let deviceCategory: DeviceCategory
    let deviceBrand: String
    let deviceModel: String
    let serialNumber: String
    let issueDescription: String?
    let priority: WorkOrderPriority
    let scheduledDate: Date
    let scheduledTimeRange: ScheduledTimeRange?

    init(
        id: WorkOrderID,
        workOrderNumber: String,
        assignedTechnicianId: UserID,
        customerId: CustomerID,
        workType: WorkType,
        deviceCategory: DeviceCategory,
        deviceBrand: String,
        deviceModel: String,
        serialNumber: String,
        issueDescription: String? = nil,
        priority: WorkOrderPriority,
        scheduledDate: Date,
        scheduledTimeRange: ScheduledTimeRange? = nil
    ) {
        self.id = id
        self.workOrderNumber = workOrderNumber
        self.assignedTechnicianId = assignedTechnicianId
        self.customerId = customerId
        self.workType = workType
        self.deviceCategory = deviceCategory
        self.deviceBrand = deviceBrand
        self.deviceModel = deviceModel
        self.serialNumber = serialNumber
        self.issueDescription = issueDescription
        self.priority = priority
        self.scheduledDate = scheduledDate
        self.scheduledTimeRange = scheduledTimeRange
    }
}

/// Creates a new work order in the `.assigned` state and records the
/// initial entry in its status-history audit trail.
///
/// Authorization: only operators may create work orders
/// (`RoleAccessPolicy.can(.createWorkOrder, as:)`).
struct CreateWorkOrderUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository
    let statusHistoryRepository: WorkOrderStatusHistoryRepository

    init(
        workOrderRepository: WorkOrderRepository,
        statusHistoryRepository: WorkOrderStatusHistoryRepository
    ) {
        self.workOrderRepository = workOrderRepository
        self.statusHistoryRepository = statusHistoryRepository
    }

    @discardableResult
    func execute(
        actor: User,
        request: NewWorkOrderRequest,
        at now: Date = Date()
    ) async throws -> WorkOrder {
        guard RoleAccessPolicy.can(.createWorkOrder, as: actor.role) else {
            throw DomainError.unauthorized(action: .createWorkOrder)
        }

        // Minimal domain-level validation. Detailed field-format
        // validation belongs to the Presentation layer.
        guard !request.deviceBrand.trimmingCharacters(in: .whitespaces).isEmpty,
              !request.deviceModel.trimmingCharacters(in: .whitespaces).isEmpty,
              !request.serialNumber.trimmingCharacters(in: .whitespaces).isEmpty,
              !request.workOrderNumber.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            throw DomainError.invalidData(reason: "workOrder.requiredFieldEmpty")
        }

        let order = WorkOrder(
            id: request.id,
            workOrderNumber: request.workOrderNumber,
            createdByUserId: actor.id,
            assignedTechnicianId: request.assignedTechnicianId,
            customerId: request.customerId,
            workType: request.workType,
            deviceCategory: request.deviceCategory,
            deviceBrand: request.deviceBrand,
            deviceModel: request.deviceModel,
            serialNumber: request.serialNumber,
            issueDescription: request.issueDescription,
            priority: request.priority,
            scheduledDate: request.scheduledDate,
            scheduledTimeRange: request.scheduledTimeRange,
            status: .assigned,
            currentPauseReason: nil,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )

        try await workOrderRepository.save(order)

        let initialHistory = WorkOrderStatusHistory(
            id: UUID().uuidString,
            workOrderId: order.id,
            fromStatus: nil,
            toStatus: .assigned,
            pauseReason: nil,
            actorUserId: actor.id,
            occurredAt: now
        )
        try await statusHistoryRepository.append(initialHistory)

        return order
    }
}
