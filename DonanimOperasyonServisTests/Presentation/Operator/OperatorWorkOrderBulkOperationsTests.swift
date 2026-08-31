import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class OperatorWorkOrderBulkOperationsTests: XCTestCase {

    private var container: DIContainer!
    private var deps: OperatorDependencies!
    private var operatorUser: User!
    private var customer: Customer!
    private var techA: User!
    private var techB: User!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeOperatorDependencies()
        operatorUser = DomainFixtures.operatorUser()
        customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        techA = DomainFixtures.technicianUser(
            id: UserID("bulk-tech-a"),
            email: "bulk-a@example.com",
            fullName: "Bulk Teknisyen A"
        )
        techB = DomainFixtures.technicianUser(
            id: UserID("bulk-tech-b"),
            email: "bulk-b@example.com",
            fullName: "Bulk Teknisyen B"
        )
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(techA)
        try await deps.userRepository.save(techB)
        try await deps.customerRepository.save(customer)
    }

    private func makeListViewModel() -> OperatorWorkOrderListViewModel {
        OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
    }

    private func seedOrders(_ orders: [WorkOrder]) async throws {
        for order in orders {
            try await container.workOrderRepository.save(order)
        }
    }

    private func ordersByID(from vm: OperatorWorkOrderListViewModel) -> [WorkOrderID: WorkOrder] {
        Dictionary(uniqueKeysWithValues: vm.displayedOrders.map { ($0.id, $0) })
    }

    func testMultipleWorkOrdersCanBeSelected() async throws {
        let order1 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-wo-1"),
            workOrderNumber: "WO-BULK-1",
            customerId: customer.id,
            status: .assigned
        )
        let order2 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-wo-2"),
            workOrderNumber: "WO-BULK-2",
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await seedOrders([order1, order2])

        let vm = makeListViewModel()
        vm.setSelectionMode(true)
        await vm.load()

        XCTAssertTrue(vm.canSelect(order1.id))
        vm.toggleSelection(order1.id)
        vm.toggleSelection(order2.id)

        XCTAssertEqual(vm.selectedCount, 2)
        XCTAssertTrue(vm.isSelected(order1.id))
        XCTAssertTrue(vm.isSelected(order2.id))
        XCTAssertEqual(vm.selectionSummaryText, "2 iş emri seçildi")
    }

    func testSelectAllAndClearSelection() async throws {
        let active = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-active"),
            customerId: customer.id,
            status: .assigned
        )
        let completed = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-completed"),
            workOrderNumber: "WO-BULK-C",
            customerId: customer.id,
            status: .completed
        )
        try await seedOrders([active, completed])

        let vm = makeListViewModel()
        vm.setSelectionMode(true)
        await vm.load()

        vm.selectAllEligible()
        XCTAssertEqual(vm.selectedCount, 1)
        XCTAssertTrue(vm.isSelected(active.id))
        XCTAssertFalse(vm.isSelected(completed.id))

        vm.clearSelection()
        XCTAssertEqual(vm.selectedCount, 0)
        XCTAssertEqual(vm.selectionSummaryText, "Seçim yok")
    }

    func testBulkAssignTechnician() async throws {
        let order1 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-assign-1"),
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )
        let order2 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-assign-2"),
            workOrderNumber: "WO-BA-2",
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )
        try await seedOrders([order1, order2])

        let vm = makeListViewModel()
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(order1.id)
        vm.toggleSelection(order2.id)

        let result = await OperatorWorkOrderBulkOperations.assignTechnician(
            orderIds: Array(vm.selectedOrderIDs),
            ordersByID: ordersByID(from: vm),
            technicianId: techB.id,
            actor: operatorUser,
            service: deps.workOrderService
        )

        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.failureCount, 0)

        let updated1 = try await container.workOrderRepository.fetch(id: order1.id)
        let updated2 = try await container.workOrderRepository.fetch(id: order2.id)
        XCTAssertEqual(updated1.assignedTechnicianId, techB.id)
        XCTAssertEqual(updated2.assignedTechnicianId, techB.id)
    }

    func testBulkPriorityUpdate() async throws {
        let order1 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-priority-1"),
            customerId: customer.id,
            priority: .normal,
            status: .assigned
        )
        let order2 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-priority-2"),
            workOrderNumber: "WO-BP-2",
            customerId: customer.id,
            priority: .normal,
            status: .assigned
        )
        try await seedOrders([order1, order2])

        let vm = makeListViewModel()
        await vm.load()
        vm.toggleSelection(order1.id)
        vm.toggleSelection(order2.id)

        let result = await OperatorWorkOrderBulkOperations.updatePriority(
            orderIds: Array(vm.selectedOrderIDs),
            ordersByID: ordersByID(from: vm),
            priority: .urgent,
            actor: operatorUser,
            service: deps.workOrderService
        )

        XCTAssertEqual(result.successCount, 2)
        let updated1 = try await container.workOrderRepository.fetch(id: order1.id)
        let updated2 = try await container.workOrderRepository.fetch(id: order2.id)
        XCTAssertEqual(updated1.priority, .urgent)
        XCTAssertEqual(updated2.priority, .urgent)
    }

    func testBulkScheduledDateUpdate() async throws {
        let newDate = DomainFixtures.referenceDate.addingTimeInterval(86_400)
        let newStart = newDate.addingTimeInterval(3600)
        let newEnd = newDate.addingTimeInterval(7200)
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-schedule-1"),
            customerId: customer.id,
            status: .assigned
        )
        try await seedOrders([order])

        let vm = makeListViewModel()
        await vm.load()
        vm.toggleSelection(order.id)

        let result = await OperatorWorkOrderBulkOperations.updateSchedule(
            orderIds: [order.id],
            ordersByID: ordersByID(from: vm),
            scheduledDate: newDate,
            scheduledTimeRange: ScheduledTimeRange(start: newStart, end: newEnd),
            actor: operatorUser,
            service: deps.workOrderService
        )

        XCTAssertEqual(result.successCount, 1)
        let updated = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(updated.scheduledDate.timeIntervalSince1970, newDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertNotNil(updated.scheduledTimeRange)
        XCTAssertEqual(updated.scheduledTimeRange!.start.timeIntervalSince1970, newStart.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(updated.scheduledTimeRange!.end.timeIntervalSince1970, newEnd.timeIntervalSince1970, accuracy: 1)
    }

    func testBulkMutationOfflineQueuesOperations() async throws {
        let order1 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-offline-1"),
            customerId: customer.id,
            status: .assigned
        )
        let order2 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-offline-2"),
            workOrderNumber: "WO-OFF-2",
            customerId: customer.id,
            status: .assigned
        )
        try await seedOrders([order1, order2])

        let reachability = FakeNetworkReachability(isReachable: false)
        let offlineDeps = makeDependencies(reachability: reachability)
        let vm = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: offlineDeps)
        await vm.load()
        vm.toggleSelection(order1.id)
        vm.toggleSelection(order2.id)

        let result = await OperatorWorkOrderBulkOperations.updatePriority(
            orderIds: Array(vm.selectedOrderIDs),
            ordersByID: ordersByID(from: vm),
            priority: .high,
            actor: operatorUser,
            service: offlineDeps.workOrderService
        )
        XCTAssertEqual(result.successCount, 2)

        for orderId in [order1.id, order2.id] {
            let ops = try await container.syncOperationRepository.list(
                entityType: .workOrder,
                entityId: orderId.rawValue
            )
            XCTAssertTrue(ops.contains { $0.operationType == .update && $0.status == .pending })
        }
    }

    func testBulkMutationOnlineSucceeds() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-online-1"),
            customerId: customer.id,
            status: .assigned
        )
        try await seedOrders([order])

        let vm = makeListViewModel()
        await vm.load()
        vm.toggleSelection(order.id)

        let result = await OperatorWorkOrderBulkOperations.updatePriority(
            orderIds: [order.id],
            ordersByID: ordersByID(from: vm),
            priority: .high,
            actor: operatorUser,
            service: deps.workOrderService
        )

        XCTAssertTrue(result.isCompleteSuccess)
        let updated = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(updated.priority, .high)
    }

    func testBulkMutationPartialFailure() async throws {
        let active = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-partial-active"),
            customerId: customer.id,
            status: .assigned
        )
        let completed = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-partial-completed"),
            workOrderNumber: "WO-PART-C",
            customerId: customer.id,
            status: .completed
        )
        try await seedOrders([active, completed])

        let vm = makeListViewModel()
        await vm.load()
        let ordersMap = ordersByID(from: vm)

        let result = await OperatorWorkOrderBulkOperations.updatePriority(
            orderIds: [active.id, completed.id],
            ordersByID: ordersMap,
            priority: .urgent,
            actor: operatorUser,
            service: deps.workOrderService
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.failureCount, 1)
        XCTAssertEqual(result.succeeded, [active.id])
        XCTAssertEqual(result.failures.first?.orderId, completed.id)

        let stillCompleted = try await container.workOrderRepository.fetch(id: completed.id)
        XCTAssertEqual(stillCompleted.priority, .normal)
    }

    func testCompletedOrdersRespectBulkMutationRules() async throws {
        let completed = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-rules-completed"),
            customerId: customer.id,
            status: .completed
        )
        let rejected = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-rules-rejected"),
            workOrderNumber: "WO-REJ",
            customerId: customer.id,
            status: .rejected
        )
        try await seedOrders([completed, rejected])

        let vm = makeListViewModel()
        await vm.load()

        XCTAssertFalse(vm.canSelect(completed.id))
        XCTAssertFalse(vm.canSelect(rejected.id))
        XCTAssertFalse(WorkOrderBulkMutationPolicy.supportsBulkPlanningMutation(completed))
        XCTAssertFalse(WorkOrderBulkMutationPolicy.supportsBulkPlanningMutation(rejected))

        let map = ordersByID(from: vm)
        let assignResult = await OperatorWorkOrderBulkOperations.assignTechnician(
            orderIds: [completed.id],
            ordersByID: map,
            technicianId: techB.id,
            actor: operatorUser,
            service: deps.workOrderService
        )
        XCTAssertEqual(assignResult.failureCount, 1)
        XCTAssertEqual(assignResult.successCount, 0)
    }

    func testBulkActionsDoNotCreateDuplicateMutations() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-dedupe"),
            customerId: customer.id,
            status: .assigned
        )
        try await seedOrders([order])

        let vm = makeListViewModel()
        await vm.load()
        let map = ordersByID(from: vm)

        let result = await OperatorWorkOrderBulkOperations.updatePriority(
            orderIds: [order.id, order.id, order.id],
            ordersByID: map,
            priority: .high,
            actor: operatorUser,
            service: deps.workOrderService
        )

        XCTAssertEqual(result.successCount, 1)

        let ops = try await container.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )
        let pendingUpdates = ops.filter { $0.operationType == .update && $0.status == .pending }
        XCTAssertEqual(pendingUpdates.count, 1)
    }

    func testBulkActionsDoNotNPlusOneFetch() async throws {
        let order1 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-n1-1"),
            customerId: customer.id,
            status: .assigned
        )
        let order2 = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-n1-2"),
            workOrderNumber: "WO-N1-2",
            customerId: customer.id,
            status: .assigned
        )
        try await seedOrders([order1, order2])

        let countingRepo = CountingBulkWorkOrderRepository(inner: container.workOrderRepository)
        let service = OperatorWorkOrderService(
            createWorkOrder: CreateWorkOrderUseCase(
                workOrderRepository: countingRepo,
                statusHistoryRepository: container.workOrderStatusHistoryRepository
            ),
            assignWorkOrder: AssignWorkOrderUseCase(workOrderRepository: countingRepo),
            updateWorkOrderPlanning: UpdateWorkOrderPlanningUseCase(workOrderRepository: countingRepo),
            statusHistoryRepository: container.workOrderStatusHistoryRepository,
            syncOperationRepository: container.syncOperationRepository,
            notificationRepository: container.notificationRepository
        )

        let vm = makeListViewModel()
        await vm.load()
        let map = ordersByID(from: vm)
        let listBefore = await countingRepo.listCallCount

        _ = await OperatorWorkOrderBulkOperations.updatePriority(
            orderIds: [order1.id, order2.id],
            ordersByID: map,
            priority: .high,
            actor: operatorUser,
            service: service
        )

        let listAfter = await countingRepo.listCallCount
        XCTAssertEqual(listBefore, listAfter)
    }

    private func makeDependencies(reachability: NetworkReachabilityProviding) -> OperatorDependencies {
        let base = container.makeOperatorDependencies()
        return OperatorDependencies (
            getWorkOrders: base.getWorkOrders,
            getWorkOrder: base.getWorkOrder,
            workOrderService: base.workOrderService,
            customerService: base.customerService,
            workOrderTemplateService: base.workOrderTemplateService,
            customerRepository: base.customerRepository,
            userRepository: base.userRepository,
            localDirectoryCacheRefresh: base.localDirectoryCacheRefresh,
            workOrderNoteRepository: base.workOrderNoteRepository,
            workOrderPhotoRepository: base.workOrderPhotoRepository,
            workOrderLocationRepository: base.workOrderLocationRepository,
            signatureRepository: base.signatureRepository,
            statusHistoryRepository: base.statusHistoryRepository,
            editRequestRepository: base.editRequestRepository,
            editRequestService: base.editRequestService,
            customerSatisfactionRepository: base.customerSatisfactionRepository,
            customerSatisfactionService: base.customerSatisfactionService,
            notificationRepository: base.notificationRepository,
            syncOperationRepository: base.syncOperationRepository,
            syncConflictRepository: base.syncConflictRepository,
            conflictResolver: base.conflictResolver,
            networkReachability: reachability,
            profileAccountService: base.profileAccountService,
            storageDataSource: base.storageDataSource
        )
    }
}

private actor CountingBulkWorkOrderRepository: WorkOrderRepository {
    let inner: any WorkOrderRepository
    private(set) var listCallCount = 0

    init(inner: any WorkOrderRepository) { self.inner = inner }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        listCallCount += 1
        return try await inner.list(filter: filter)
    }

    func fetch(id: WorkOrderID) async throws -> WorkOrder { try await inner.fetch(id: id) }
    func save(_ workOrder: WorkOrder) async throws { try await inner.save(workOrder) }
    func delete(id: WorkOrderID) async throws { try await inner.delete(id: id) }
}
